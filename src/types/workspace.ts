import type { BusinessRole, WorkspaceRole } from "@/lib/permissions";

export interface WorkspaceSummary {
  id: string;
  name: string;
  timezone: string;
}

export interface WorkspaceMembership {
  workspace_id: string;
  role: WorkspaceRole;
  business_role: BusinessRole;
  workspaces: WorkspaceSummary | null;
}

export interface WorkspaceMemberSummary {
  user_id: string;
  role: WorkspaceRole;
  business_role: BusinessRole;
  profiles: {
    display_name: string;
  } | null;
}
