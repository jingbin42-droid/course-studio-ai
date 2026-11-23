import { describe, expect, it } from "vitest";

import { getAuthErrorMessage, getErrorMessage } from "@/lib/errors";

describe("error helpers", () => {
  it("turns common auth errors into friendly Chinese messages", () => {
    expect(getAuthErrorMessage("Invalid login credentials")).toBe(
      "邮箱或密码不正确。",
    );
  });

  it("handles non-error values safely", () => {
    expect(getErrorMessage(null)).toBe("发生了未知错误，请稍后重试。");
  });
});
