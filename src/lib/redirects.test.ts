import { describe, expect, it } from "vitest";

import { getSafeNextPath } from "@/lib/redirects";

describe("getSafeNextPath", () => {
  it("preserves an internal invitation path", () => {
    expect(getSafeNextPath("/app?invite=abc-123")).toBe(
      "/app?invite=abc-123",
    );
  });

  it("rejects external and protocol-relative destinations", () => {
    expect(getSafeNextPath("https://example.com")).toBe("/app");
    expect(getSafeNextPath("//example.com/path")).toBe("/app");
  });

  it("uses the workspace as the default", () => {
    expect(getSafeNextPath(undefined)).toBe("/app");
  });
});
