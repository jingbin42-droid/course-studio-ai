export type WorkspaceRole = "owner" | "member";
export type BusinessRole = "A" | "B" | "C";

export function canManageWorkspace(role: WorkspaceRole): boolean {
  return role === "owner";
}

export function isBusinessRole(value: string): value is BusinessRole {
  return value === "A" || value === "B" || value === "C";
}
