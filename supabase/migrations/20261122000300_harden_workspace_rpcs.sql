-- Course Studio AI · Phase 1 follow-up
-- Harden workspace RPC input validation and invitation acceptance semantics.

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

  if workspace_name is null or trim(workspace_name) = '' then
    raise exception 'workspace name is required';
  end if;

  if char_length(trim(workspace_name)) > 120 then
    raise exception 'workspace name is invalid';
  end if;

  if workspace_timezone is null or trim(workspace_timezone) = '' then
    raise exception 'workspace timezone is required';
  end if;

  if char_length(trim(workspace_timezone)) > 100 then
    raise exception 'workspace timezone is invalid';
  end if;

  if member_business_role is null then
    raise exception 'business role is required';
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
  normalized_email text;
  invitation_token uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not private.has_workspace_role(target_workspace_id, 'owner') then
    raise exception 'owner permission required';
  end if;

  if invitee_email is null or trim(invitee_email) = '' then
    raise exception 'invitee email is required';
  end if;

  normalized_email := lower(trim(invitee_email));

  if char_length(normalized_email) > 320
    or normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'valid email required';
  end if;

  if invitee_business_role is null then
    raise exception 'business role is required';
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
  inserted_workspace_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if invitation_token is null then
    raise exception 'invitation is invalid or expired';
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

  if invitation.role <> 'member' then
    raise exception 'invitation role is invalid';
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
  on conflict (workspace_id, user_id) do nothing
  returning workspace_id into inserted_workspace_id;

  if inserted_workspace_id is null then
    raise exception 'user is already a workspace member';
  end if;

  update public.workspace_invitations
  set
    status = 'accepted',
    accepted_by = auth.uid(),
    accepted_at = now()
  where id = invitation.id;

  return invitation.workspace_id;
end;
$$;

-- CREATE OR REPLACE preserves existing privileges. Reassert the intended
-- least-privilege boundary after replacing each public RPC.
revoke all on function public.create_workspace(text, text, public.business_role)
  from public, anon, authenticated;
revoke all on function public.create_workspace_invitation(uuid, text, public.business_role)
  from public, anon, authenticated;
revoke all on function public.accept_workspace_invitation(uuid)
  from public, anon, authenticated;

grant execute on function public.create_workspace(text, text, public.business_role)
  to authenticated;
grant execute on function public.create_workspace_invitation(uuid, text, public.business_role)
  to authenticated;
grant execute on function public.accept_workspace_invitation(uuid)
  to authenticated;
