import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const migrationsDirectory = resolve(process.cwd(), "supabase", "migrations");

function readMigration(fileName: string): Buffer {
  return readFileSync(resolve(migrationsDirectory, fileName));
}

function sha256(content: Buffer): string {
  return createHash("sha256").update(content).digest("hex");
}

const hardeningMigration = readMigration(
  "20261122000300_harden_workspace_rpcs.sql",
).toString("utf8");

describe("deployed migration history", () => {
  it("keeps the deployed identity schema migration unchanged", () => {
    expect(
      sha256(readMigration("20261122000100_identity_schema.sql")),
    ).toBe("25a05f0c48c7be57986fae71942e1a54d79635a02417078e5fdb515cb54435d4");
  });

  it("keeps the deployed identity RLS migration unchanged", () => {
    expect(
      sha256(readMigration("20261122000200_identity_rls.sql")),
    ).toBe("bb2099d5a6f44fc53bd790389d3f7c9d2c51b1d83d318309aa0f7627515ca1f7");
  });
});

describe("workspace RPC hardening migration", () => {
  it("preserves all public RPC signatures", () => {
    expect(hardeningMigration).toContain(
      "public.create_workspace(\n  workspace_name text,\n  workspace_timezone text,\n  member_business_role public.business_role",
    );
    expect(hardeningMigration).toContain(
      "public.create_workspace_invitation(\n  target_workspace_id uuid,\n  invitee_email text,\n  invitee_business_role public.business_role",
    );
    expect(hardeningMigration).toContain(
      "public.accept_workspace_invitation(\n  invitation_token uuid",
    );
  });

  it("rejects missing workspace inputs and preserves owner creation", () => {
    expect(hardeningMigration).toMatch(
      /workspace_name is null or trim\(workspace_name\) = ''/,
    );
    expect(hardeningMigration).toMatch(
      /workspace_timezone is null or trim\(workspace_timezone\) = ''/,
    );
    expect(hardeningMigration).toContain(
      "char_length(trim(workspace_name)) > 120",
    );
    expect(hardeningMigration).toContain(
      "char_length(trim(workspace_timezone)) > 100",
    );
    expect(hardeningMigration).toContain("member_business_role is null");
    expect(hardeningMigration).toMatch(/auth\.uid\(\)[\s\S]*?'owner'/);
  });

  it("normalizes invitations and limits business roles to the enum", () => {
    expect(hardeningMigration).toMatch(
      /invitee_email is null or trim\(invitee_email\) = ''/,
    );
    expect(hardeningMigration).toContain(
      "normalized_email := lower(trim(invitee_email))",
    );
    expect(hardeningMigration).toContain("invitee_business_role is null");
    expect(hardeningMigration).toContain(
      "invitee_business_role public.business_role",
    );
    expect(hardeningMigration).toContain(
      "private.has_workspace_role(target_workspace_id, 'owner')",
    );
    expect(hardeningMigration).toMatch(
      /set status = 'revoked'[\s\S]*?and status = 'pending'/,
    );
  });

  it("serializes invitation acceptance and rejects duplicate members", () => {
    expect(hardeningMigration).toContain("invitation_token is null");
    expect(hardeningMigration).toMatch(/where token = invitation_token\s+for update/);
    expect(hardeningMigration).toMatch(
      /invitation\.status <> 'pending'[\s\S]*?invitation\.expires_at <= now\(\)/,
    );
    expect(hardeningMigration).toContain(
      "current_email <> invitation.email",
    );
    expect(hardeningMigration).toContain("invitation.role <> 'member'");
    expect(hardeningMigration).toMatch(
      /'member',\s+invitation\.business_role/,
    );
    expect(hardeningMigration).toMatch(
      /on conflict \(workspace_id, user_id\) do nothing\s+returning workspace_id into inserted_workspace_id/,
    );
    expect(hardeningMigration).toContain("inserted_workspace_id is null");
  });

  it("pins security definer search paths and reasserts least privilege", () => {
    expect(hardeningMigration.match(/security definer/g)).toHaveLength(3);
    expect(hardeningMigration.match(/set search_path = ''/g)).toHaveLength(3);
    expect(hardeningMigration.match(/from public, anon, authenticated/g)).toHaveLength(3);
    expect(hardeningMigration.match(/to authenticated;/g)).toHaveLength(3);
    expect(hardeningMigration).not.toMatch(/grant execute[^;]+to (?:anon|public)/i);
  });

  it("contains no destructive migration statements", () => {
    expect(hardeningMigration).not.toMatch(
      /\b(?:drop|truncate)\b|\bdelete\s+from\b|disable\s+row\s+level\s+security/i,
    );
  });
});
