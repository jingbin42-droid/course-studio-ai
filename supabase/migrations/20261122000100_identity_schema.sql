-- Course Studio AI · Phase 1
-- Identity and workspace schema only. Business modules intentionally excluded.

create extension if not exists pgcrypto;

create type public.workspace_role as enum ('owner', 'member');
create type public.business_role as enum ('A', 'B', 'C');
create type public.invitation_status as enum (
  'pending',
  'accepted',
  'revoked',
  'expired'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 120),
  timezone text not null check (char_length(trim(timezone)) between 1 and 100),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.workspace_role not null default 'member',
  business_role public.business_role not null,
  joined_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table public.workspace_invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  email text not null check (email = lower(trim(email)) and char_length(email) between 3 and 320),
  role public.workspace_role not null default 'member' check (role = 'member'),
  business_role public.business_role not null,
  status public.invitation_status not null default 'pending',
  token uuid not null unique default gen_random_uuid(),
  invited_by uuid not null references auth.users (id) on delete restrict,
  accepted_by uuid references auth.users (id) on delete set null,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workspace_members_user_id_idx
  on public.workspace_members (user_id);

create index workspace_invitations_workspace_status_idx
  on public.workspace_invitations (workspace_id, status);

create unique index workspace_invitations_pending_email_idx
  on public.workspace_invitations (workspace_id, email)
  where status = 'pending';

-- Fail closed as soon as the tables exist. Policies and the minimum grants are
-- added by the next migration after the authorization helpers are available.
alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_invitations enable row level security;

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.workspaces from anon, authenticated;
revoke all on table public.workspace_members from anon, authenticated;
revoke all on table public.workspace_invitations from anon, authenticated;

comment on table public.workspaces is
  'Team workspaces. All business data will be scoped to one workspace.';

comment on column public.workspaces.timezone is
  'IANA timezone used for workspace business dates.';

comment on table public.workspace_members is
  'Membership and the independent owner/member plus A/B/C role model.';
