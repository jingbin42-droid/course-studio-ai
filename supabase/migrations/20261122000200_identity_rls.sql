-- Course Studio AI · Phase 1
-- Auth profile trigger, secure workspace RPCs, and RLS policies.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger workspaces_set_updated_at
before update on public.workspaces
for each row execute function private.set_updated_at();

create trigger workspace_invitations_set_updated_at
before update on public.workspace_invitations
for each row execute function private.set_updated_at();

create or replace function private.validate_workspace_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = new.timezone
  ) then
    raise exception 'invalid IANA timezone';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_workspace_timezone() from public, anon, authenticated;

create trigger workspaces_validate_timezone
before insert or update of timezone on public.workspaces
for each row execute function private.validate_workspace_timezone();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'member'), '@', 1)
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id, display_name)
select
  users.id,
  coalesce(
    nullif(trim(users.raw_user_meta_data ->> 'display_name'), ''),
    split_part(coalesce(users.email, 'member'), '@', 1)
  )
from auth.users as users
on conflict (id) do nothing;

create or replace function private.is_workspace_member(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_members
    where workspace_id = target_workspace_id
      and user_id = auth.uid()
  );
$$;

create or replace function private.has_workspace_role(
  target_workspace_id uuid,
  required_role public.workspace_role
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_members
    where workspace_id = target_workspace_id
      and user_id = auth.uid()
      and role = required_role
  );
$$;

revoke all on function private.is_workspace_member(uuid) from public, anon, authenticated;
revoke all on function private.has_workspace_role(uuid, public.workspace_role) from public, anon, authenticated;
grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.has_workspace_role(uuid, public.workspace_role) to authenticated;

alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_invitations enable row level security;

create policy "profiles_select_shared_workspace"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or exists (
    select 1
    from public.workspace_members target_membership
    where target_membership.user_id = profiles.id
      and private.is_workspace_member(target_membership.workspace_id)
  )
);

create policy "profiles_update_self"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "workspaces_select_member"
on public.workspaces
for select
to authenticated
using (private.is_workspace_member(id));

create policy "workspaces_update_owner"
on public.workspaces
for update
to authenticated
using (private.has_workspace_role(id, 'owner'))
with check (private.has_workspace_role(id, 'owner'));

create policy "workspace_members_select_member"
on public.workspace_members
for select
to authenticated
using (private.is_workspace_member(workspace_id));

create policy "workspace_invitations_select_owner"
on public.workspace_invitations
for select
to authenticated
using (private.has_workspace_role(workspace_id, 'owner'));

-- The first migration revoked every client-facing table privilege. Restore only
-- the operations backed by the policies above; writes that establish membership
-- or invitations remain available exclusively through the secured RPCs below.
grant select on table public.profiles to authenticated;
grant update (display_name, avatar_url) on table public.profiles to authenticated;
grant select on table public.workspaces to authenticated;
grant update (name, timezone) on table public.workspaces to authenticated;
grant select on table public.workspace_members to authenticated;
grant select on table public.workspace_invitations to authenticated;

create or replace function public.create_workspace(
  workspace_name text,
  workspace_timezone text,
  member_business_role public.business_role
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_workspace_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if char_length(trim(workspace_name)) not between 1 and 120 then
    raise exception 'workspace name is invalid';
  end if;

  if char_length(trim(workspace_timezone)) not between 1 and 100 then
    raise exception 'workspace timezone is invalid';
  end if;

  insert into public.workspaces (name, timezone, created_by)
  values (trim(workspace_name), trim(workspace_timezone), auth.uid())
  returning id into new_workspace_id;

  insert into public.workspace_members (
    workspace_id,
    user_id,
    role,
    business_role
  ) values (
    new_workspace_id,
    auth.uid(),
    'owner',
    member_business_role
  );

  return new_workspace_id;
end;
$$;

create or replace function public.create_workspace_invitation(
  target_workspace_id uuid,
  invitee_email text,
  invitee_business_role public.business_role
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(invitee_email));
  invitation_token uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not private.has_workspace_role(target_workspace_id, 'owner') then
    raise exception 'owner permission required';
  end if;

  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'valid email required';
  end if;

  update public.workspace_invitations
  set status = 'revoked'
  where workspace_id = target_workspace_id
    and email = normalized_email
    and status = 'pending';

  insert into public.workspace_invitations (
    workspace_id,
    email,
    business_role,
    invited_by
  ) values (
    target_workspace_id,
    normalized_email,
    invitee_business_role,
    auth.uid()
  )
  returning token into invitation_token;

  return invitation_token;
end;
$$;

create or replace function public.accept_workspace_invitation(
  invitation_token uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.workspace_invitations%rowtype;
  current_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select *
  into invitation
  from public.workspace_invitations
  where token = invitation_token
  for update;

  if invitation.id is null
    or invitation.status <> 'pending'
    or invitation.expires_at <= now() then
    raise exception 'invitation is invalid or expired';
  end if;

  if current_email = '' or current_email <> invitation.email then
    raise exception 'invitation email does not match current user';
  end if;

  insert into public.workspace_members (
    workspace_id,
    user_id,
    role,
    business_role
  ) values (
    invitation.workspace_id,
    auth.uid(),
    'member',
    invitation.business_role
  )
  on conflict (workspace_id, user_id) do nothing;

  update public.workspace_invitations
  set
    status = 'accepted',
    accepted_by = auth.uid(),
    accepted_at = now()
  where id = invitation.id;

  return invitation.workspace_id;
end;
$$;

revoke all on function public.create_workspace(text, text, public.business_role) from public, anon, authenticated;
revoke all on function public.create_workspace_invitation(uuid, text, public.business_role) from public, anon, authenticated;
revoke all on function public.accept_workspace_invitation(uuid) from public, anon, authenticated;

grant execute on function public.create_workspace(text, text, public.business_role) to authenticated;
grant execute on function public.create_workspace_invitation(uuid, text, public.business_role) to authenticated;
grant execute on function public.accept_workspace_invitation(uuid) to authenticated;
