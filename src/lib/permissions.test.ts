import { describe, expect, it } from "vitest";

import { canManageWorkspace, isBusinessRole } from "@/lib/permissions";

describe("workspace permissions", () => {
  it("allows only owners to manage workspace settings", () => {
    expect(canManageWorkspace("owner")).toBe(true);
    expect(canManageWorkspace("member")).toBe(false);
  });

  it("accepts only the three agreed business roles", () => {
    expect(isBusinessRole("A")).toBe(true);
    expect(isBusinessRole("B")).toBe(true);
    expect(isBusinessRole("C")).toBe(true);
    expect(isBusinessRole("admin")).toBe(false);
  });
});
