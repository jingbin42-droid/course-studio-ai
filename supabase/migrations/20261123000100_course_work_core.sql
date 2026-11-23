-- Course Studio AI · Phase 2/3 core
-- Course projects, work items, work logs, daily reports, AI artifacts,
-- project events and owner member-management RPCs.
-- Every table is workspace scoped and protected by RLS. Writes that would
-- cross workspaces are rejected by composite foreign keys and policies.

-- ---------------------------------------------------------------------------
-- Enums (values follow docs/AGENTS.md terminology)
-- ---------------------------------------------------------------------------

create type public.course_stage as enum (
  'idea', 'planning', 'production', 'promotion', 'launch', 'operation', 'archived'
);
create type public.course_health as enum ('on_track', 'at_risk', 'off_track');
create type public.workstream as enum ('production', 'promotion', 'operation', 'shared');
create type public.work_item_status as enum (
  'backlog', 'ready', 'in_progress', 'blocked', 'review', 'done', 'cancelled'
);
create type public.work_item_priority as enum ('low', 'medium', 'high', 'urgent');
create type public.work_log_visibility as enum ('team', 'private');
create type public.daily_report_type as enum ('personal_daily', 'team_daily');
create type public.ai_content_status as enum ('draft', 'accepted', 'edited', 'dismissed');
create type public.ai_artifact_status as enum ('draft', 'accepted', 'edited', 'dismissed', 'failed');
create type public.ai_artifact_type as enum ('daily_report', 'partner_answer');

-- ---------------------------------------------------------------------------
-- Authorization helper: is a given user a member of the workspace?
-- ---------------------------------------------------------------------------

create or replace function private.is_workspace_user(
  target_workspace_id uuid,
  target_user_id uuid
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
      and user_id = target_user_id
  );
$$;

revoke all on function private.is_workspace_user(uuid, uuid) from public, anon, authenticated;
grant execute on function private.is_workspace_user(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.course_projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  summary text check (summary is null or char_length(summary) <= 4000),
  audience text check (audience is null or char_length(audience) <= 1000),
  core_promise text check (core_promise is null or char_length(core_promise) <= 1000),
  stage public.course_stage not null default 'idea',
  health public.course_health not null default 'on_track',
  owner_id uuid references public.profiles (id) on delete set null,
  target_launch_at timestamptz,
  target_sales_at timestamptz,
  created_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, workspace_id)
);

create table public.work_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  course_project_id uuid not null,
  title text not null check (char_length(trim(title)) between 1 and 200),
  description text check (description is null or char_length(description) <= 8000),
  workstream public.workstream not null default 'shared',
  status public.work_item_status not null default 'backlog',
  priority public.work_item_priority not null default 'medium',
  assignee_id uuid references public.profiles (id) on delete set null,
  due_at timestamptz,
  blocked_reason text check (blocked_reason is null or char_length(blocked_reason) <= 1000),
  completed_at timestamptz,
  created_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, workspace_id),
  foreign key (course_project_id, workspace_id)
    references public.course_projects (id, workspace_id) on delete cascade
);

create table public.work_logs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete restrict,
  course_project_id uuid,
  work_item_id uuid,
  raw_text text not null check (char_length(trim(raw_text)) between 1 and 5000),
  log_date date not null,
  visibility public.work_log_visibility not null default 'team',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_project_id, workspace_id)
    references public.course_projects (id, workspace_id) on delete set null (course_project_id),
  foreign key (work_item_id, workspace_id)
    references public.work_items (id, workspace_id) on delete set null (work_item_id)
);

create table public.ai_artifacts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete restrict,
  course_project_id uuid,
  artifact_type public.ai_artifact_type not null,
  prompt_version text not null check (char_length(prompt_version) between 1 and 60),
  model text not null check (char_length(model) between 1 and 120),
  input_summary jsonb not null default '{}'::jsonb,
  output jsonb,
  status public.ai_artifact_status not null default 'draft',
  error_code text check (error_code is null or char_length(error_code) <= 120),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  usage jsonb,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (course_project_id, workspace_id)
    references public.course_projects (id, workspace_id) on delete set null (course_project_id)
);

create table public.daily_reports (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  report_type public.daily_report_type not null,
  report_date date not null,
  subject_user_id uuid references public.profiles (id) on delete restrict,
  content jsonb not null default '{}'::jsonb,
  rendered_text text not null default '' check (char_length(rendered_text) <= 20000),
  status public.ai_content_status not null default 'draft',
  generated_by_artifact_id uuid references public.ai_artifacts (id) on delete set null,
  created_by uuid not null references public.profiles (id) on delete restrict,
  confirmed_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((report_type = 'personal_daily') = (subject_user_id is not null)),
  unique nulls not distinct (workspace_id, report_type, report_date, subject_user_id)
);

create table public.project_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  course_project_id uuid,
  actor_id uuid references public.profiles (id) on delete set null,
  event_type text not null check (char_length(event_type) between 1 and 80),
  entity_type text not null check (char_length(entity_type) between 1 and 40),
  entity_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  foreign key (course_project_id, workspace_id)
    references public.course_projects (id, workspace_id) on delete set null (course_project_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index course_projects_workspace_stage_idx
  on public.course_projects (workspace_id, stage, target_launch_at);
create index work_items_workspace_assignee_idx
  on public.work_items (workspace_id, assignee_id, status, due_at);
create index work_items_course_workstream_idx
  on public.work_items (course_project_id, workstream, status);
create index work_logs_workspace_author_date_idx
  on public.work_logs (workspace_id, author_id, log_date);
create index work_logs_workspace_date_idx
  on public.work_logs (workspace_id, log_date);
create index ai_artifacts_workspace_creator_idx
  on public.ai_artifacts (workspace_id, created_by, created_at desc);
create index daily_reports_workspace_date_idx
  on public.daily_reports (workspace_id, report_date, report_type, subject_user_id);
create index project_events_course_occurred_idx
  on public.project_events (course_project_id, occurred_at desc);
create index project_events_workspace_occurred_idx
  on public.project_events (workspace_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Row maintenance triggers
-- ---------------------------------------------------------------------------

create trigger course_projects_set_updated_at
before update on public.course_projects
for each row execute function private.set_updated_at();

create trigger work_items_set_updated_at
before update on public.work_items
for each row execute function private.set_updated_at();

create trigger work_logs_set_updated_at
before update on public.work_logs
for each row execute function private.set_updated_at();

create trigger daily_reports_set_updated_at
before update on public.daily_reports
for each row execute function private.set_updated_at();

create or replace function private.maintain_course_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.stage = 'archived' then
    new.archived_at = coalesce(new.archived_at, now());
  else
    new.archived_at = null;
  end if;

  return new;
end;
$$;

revoke all on function private.maintain_course_project() from public, anon, authenticated;

create trigger course_projects_maintain
before insert or update on public.course_projects
for each row execute function private.maintain_course_project();

create or replace function private.maintain_work_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'done' then
    if tg_op = 'INSERT' or old.status is distinct from 'done' then
      new.completed_at = now();
    end if;
  else
    new.completed_at = null;
  end if;

  if new.status <> 'blocked' then
    new.blocked_reason = null;
  end if;

  return new;
end;
$$;

revoke all on function private.maintain_work_item() from public, anon, authenticated;

create trigger work_items_maintain
before insert or update on public.work_items
for each row execute function private.maintain_work_item();

-- Confirmation metadata is always derived from the acting user, never trusted
-- from client input.
create or replace function private.maintain_daily_report()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status in ('accepted', 'edited') then
    if tg_op = 'INSERT'
      or old.status not in ('accepted', 'edited')
      or new.rendered_text is distinct from old.rendered_text then
      new.confirmed_by = auth.uid();
      new.confirmed_at = now();
    end if;
  else
    new.confirmed_by = null;
    new.confirmed_at = null;
  end if;

  return new;
end;
$$;

revoke all on function private.maintain_daily_report() from public, anon, authenticated;

create trigger daily_reports_maintain
before insert or update on public.daily_reports
for each row execute function private.maintain_daily_report();

-- ---------------------------------------------------------------------------
-- Project events (append-only, written only by triggers)
-- ---------------------------------------------------------------------------

create or replace function private.record_course_project_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.project_events (
      workspace_id, course_project_id, actor_id, event_type, entity_type, entity_id, payload
    ) values (
      new.workspace_id, new.id, auth.uid(), 'course.created', 'course_project', new.id,
      jsonb_build_object('title', new.title, 'stage', new.stage)
    );
    return new;
  end if;

  if new.stage is distinct from old.stage then
    insert into public.project_events (
      workspace_id, course_project_id, actor_id, event_type, entity_type, entity_id, payload
    ) values (
      new.workspace_id, new.id, auth.uid(), 'course.stage_changed', 'course_project', new.id,
      jsonb_build_object('title', new.title, 'from', old.stage, 'to', new.stage)
    );
  end if;

  if new.health is distinct from old.health then
    insert into public.project_events (
      workspace_id, course_project_id, actor_id, event_type, entity_type, entity_id, payload
    ) values (
      new.workspace_id, new.id, auth.uid(), 'course.health_changed', 'course_project', new.id,
      jsonb_build_object('title', new.title, 'from', old.health, 'to', new.health)
    );
  end if;

  return new;
end;
$$;

revoke all on function private.record_course_project_event() from public, anon, authenticated;

create trigger course_projects_record_event
after insert or update on public.course_projects
for each row execute function private.record_course_project_event();

create or replace function private.record_work_item_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.project_events (
      workspace_id, course_project_id, actor_id, event_type, entity_type, entity_id, payload
    ) values (
      new.workspace_id, new.course_project_id, auth.uid(), 'work_item.created', 'work_item', new.id,
      jsonb_build_object('title', new.title, 'status', new.status, 'assignee_id', new.assignee_id)
    );
    return new;
  end if;

  if new.status is distinct from old.status then
    insert into public.project_events (
      workspace_id, course_project_id, actor_id, event_type, entity_type, entity_id, payload
    ) values (
      new.workspace_id, new.course_project_id, auth.uid(), 'work_item.status_changed', 'work_item', new.id,
      jsonb_build_object('title', new.title, 'from', old.status, 'to', new.status)
    );
  end if;

  if new.assignee_id is distinct from old.assignee_id then
    insert into public.project_events (
      workspace_id, course_project_id, actor_id, event_type, entity_type, entity_id, payload
    ) values (
      new.workspace_id, new.course_project_id, auth.uid(), 'work_item.assigned', 'work_item', new.id,
      jsonb_build_object('title', new.title, 'from', old.assignee_id, 'to', new.assignee_id)
    );
  end if;

  return new;
end;
$$;

revoke all on function private.record_work_item_event() from public, anon, authenticated;

create trigger work_items_record_event
after insert or update on public.work_items
for each row execute function private.record_work_item_event();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.course_projects enable row level security;
alter table public.work_items enable row level security;
alter table public.work_logs enable row level security;
alter table public.ai_artifacts enable row level security;
alter table public.daily_reports enable row level security;
alter table public.project_events enable row level security;

revoke all on table public.course_projects from anon, authenticated;
revoke all on table public.work_items from anon, authenticated;
revoke all on table public.work_logs from anon, authenticated;
revoke all on table public.ai_artifacts from anon, authenticated;
revoke all on table public.daily_reports from anon, authenticated;
revoke all on table public.project_events from anon, authenticated;

-- course_projects: shared team data; delete limited to owner or creator.
create policy "course_projects_select_member"
on public.course_projects for select to authenticated
using (private.is_workspace_member(workspace_id));

create policy "course_projects_insert_member"
on public.course_projects for insert to authenticated
with check (
  private.is_workspace_member(workspace_id)
  and created_by = auth.uid()
  and (owner_id is null or private.is_workspace_user(workspace_id, owner_id))
);

create policy "course_projects_update_member"
on public.course_projects for update to authenticated
using (private.is_workspace_member(workspace_id))
with check (
  private.is_workspace_member(workspace_id)
  and (owner_id is null or private.is_workspace_user(workspace_id, owner_id))
);

create policy "course_projects_delete_owner_or_creator"
on public.course_projects for delete to authenticated
using (
  private.has_workspace_role(workspace_id, 'owner')
  or (created_by = auth.uid() and private.is_workspace_member(workspace_id))
);

-- work_items: shared team data; assignee must belong to the same workspace.
create policy "work_items_select_member"
on public.work_items for select to authenticated
using (private.is_workspace_member(workspace_id));

create policy "work_items_insert_member"
on public.work_items for insert to authenticated
with check (
  private.is_workspace_member(workspace_id)
  and created_by = auth.uid()
  and (assignee_id is null or private.is_workspace_user(workspace_id, assignee_id))
);

create policy "work_items_update_member"
on public.work_items for update to authenticated
using (private.is_workspace_member(workspace_id))
with check (
  private.is_workspace_member(workspace_id)
  and (assignee_id is null or private.is_workspace_user(workspace_id, assignee_id))
);

create policy "work_items_delete_owner_or_creator"
on public.work_items for delete to authenticated
using (
  private.has_workspace_role(workspace_id, 'owner')
  or (created_by = auth.uid() and private.is_workspace_member(workspace_id))
);

-- work_logs: private logs are readable only by their author.
create policy "work_logs_select_visible"
on public.work_logs for select to authenticated
using (
  private.is_workspace_member(workspace_id)
  and (visibility = 'team' or author_id = auth.uid())
);

create policy "work_logs_insert_author"
on public.work_logs for insert to authenticated
with check (
  private.is_workspace_member(workspace_id)
  and author_id = auth.uid()
);

create policy "work_logs_update_author"
on public.work_logs for update to authenticated
using (author_id = auth.uid() and private.is_workspace_member(workspace_id))
with check (author_id = auth.uid() and private.is_workspace_member(workspace_id));

create policy "work_logs_delete_author"
on public.work_logs for delete to authenticated
using (author_id = auth.uid() and private.is_workspace_member(workspace_id));

-- ai_artifacts: personal AI call audit records.
create policy "ai_artifacts_select_creator"
on public.ai_artifacts for select to authenticated
using (created_by = auth.uid() and private.is_workspace_member(workspace_id));

create policy "ai_artifacts_insert_creator"
on public.ai_artifacts for insert to authenticated
with check (created_by = auth.uid() and private.is_workspace_member(workspace_id));

create policy "ai_artifacts_update_creator"
on public.ai_artifacts for update to authenticated
using (created_by = auth.uid() and private.is_workspace_member(workspace_id))
with check (created_by = auth.uid() and private.is_workspace_member(workspace_id));

-- daily_reports: team reports are shared; personal drafts stay with their
-- subject until confirmed.
create policy "daily_reports_select_visible"
on public.daily_reports for select to authenticated
using (
  private.is_workspace_member(workspace_id)
  and (
    report_type = 'team_daily'
    or subject_user_id = auth.uid()
    or status in ('accepted', 'edited')
  )
);

create policy "daily_reports_insert_member"
on public.daily_reports for insert to authenticated
with check (
  private.is_workspace_member(workspace_id)
  and created_by = auth.uid()
  and (report_type = 'team_daily' or subject_user_id = auth.uid())
);

create policy "daily_reports_update_member"
on public.daily_reports for update to authenticated
using (
  private.is_workspace_member(workspace_id)
  and (report_type = 'team_daily' or subject_user_id = auth.uid())
)
with check (
  private.is_workspace_member(workspace_id)
  and (report_type = 'team_daily' or subject_user_id = auth.uid())
);

-- project_events: read-only for members; written by security definer triggers.
create policy "project_events_select_member"
on public.project_events for select to authenticated
using (private.is_workspace_member(workspace_id));

-- workspace_members: owners may adjust A/B/C business roles.
create policy "workspace_members_update_owner"
on public.workspace_members for update to authenticated
using (private.has_workspace_role(workspace_id, 'owner'))
with check (private.has_workspace_role(workspace_id, 'owner'));

-- Minimal grants backing the policies above. Identity columns such as
-- workspace_id, created_by and author_id can never be changed after insert.
grant select, delete on table public.course_projects to authenticated;
grant insert (
  workspace_id, title, summary, audience, core_promise, stage, health,
  owner_id, target_launch_at, target_sales_at, created_by
) on table public.course_projects to authenticated;
grant update (
  title, summary, audience, core_promise, stage, health,
  owner_id, target_launch_at, target_sales_at
) on table public.course_projects to authenticated;

grant select, delete on table public.work_items to authenticated;
grant insert (
  workspace_id, course_project_id, title, description, workstream, status,
  priority, assignee_id, due_at, blocked_reason, created_by
) on table public.work_items to authenticated;
grant update (
  course_project_id, title, description, workstream, status, priority,
  assignee_id, due_at, blocked_reason
) on table public.work_items to authenticated;

grant select, delete on table public.work_logs to authenticated;
grant insert (
  workspace_id, author_id, course_project_id, work_item_id, raw_text, log_date, visibility
) on table public.work_logs to authenticated;
grant update (
  course_project_id, work_item_id, raw_text, log_date, visibility
) on table public.work_logs to authenticated;

grant select on table public.ai_artifacts to authenticated;
grant insert (
  workspace_id, created_by, course_project_id, artifact_type, prompt_version, model,
  input_summary, output, status, error_code, latency_ms, usage
) on table public.ai_artifacts to authenticated;
grant update (status, resolved_at) on table public.ai_artifacts to authenticated;

grant select on table public.daily_reports to authenticated;
grant insert (
  workspace_id, report_type, report_date, subject_user_id, content, rendered_text,
  status, generated_by_artifact_id, created_by
) on table public.daily_reports to authenticated;
grant update (
  content, rendered_text, status, generated_by_artifact_id
) on table public.daily_reports to authenticated;

grant select on table public.project_events to authenticated;

grant update (business_role) on table public.workspace_members to authenticated;

-- ---------------------------------------------------------------------------
-- Owner member-management RPCs
-- ---------------------------------------------------------------------------

create or replace function public.remove_workspace_member(
  target_workspace_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if target_workspace_id is null or target_user_id is null then
    raise exception 'workspace and member are required';
  end if;

  if not private.has_workspace_role(target_workspace_id, 'owner') then
    raise exception 'owner permission required';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'owner cannot remove themselves';
  end if;

  delete from public.workspace_members
  where workspace_id = target_workspace_id
    and user_id = target_user_id
    and role = 'member'
  returning user_id into removed_user_id;

  if removed_user_id is null then
    raise exception 'member not found';
  end if;

  -- Open responsibilities return to the team instead of pointing at someone
  -- who can no longer see the workspace. History is preserved.
  update public.work_items
  set assignee_id = null
  where workspace_id = target_workspace_id
    and assignee_id = target_user_id
    and status not in ('done', 'cancelled');

  update public.course_projects
  set owner_id = null
  where workspace_id = target_workspace_id
    and owner_id = target_user_id;
end;
$$;

create or replace function public.revoke_workspace_invitation(
  target_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_workspace_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select workspace_id
  into invitation_workspace_id
  from public.workspace_invitations
  where id = target_invitation_id
  for update;

  if invitation_workspace_id is null then
    raise exception 'invitation not found';
  end if;

  if not private.has_workspace_role(invitation_workspace_id, 'owner') then
    raise exception 'owner permission required';
  end if;

  update public.workspace_invitations
  set status = 'revoked'
  where id = target_invitation_id
    and status = 'pending';
end;
$$;

revoke all on function public.remove_workspace_member(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.revoke_workspace_invitation(uuid)
  from public, anon, authenticated;

grant execute on function public.remove_workspace_member(uuid, uuid)
  to authenticated;
grant execute on function public.revoke_workspace_invitation(uuid)
  to authenticated;

comment on table public.course_projects is
  'One course project carries production, promotion, launch and operation context.';
comment on table public.work_logs is
  'Raw natural-language work records. AI output is never written back to raw_text.';
comment on table public.ai_artifacts is
  'Audit record of every AI call: purpose, model, minimal input summary, output and status.';
comment on table public.daily_reports is
  'Personal and team daily reports. AI drafts require human confirmation.';
