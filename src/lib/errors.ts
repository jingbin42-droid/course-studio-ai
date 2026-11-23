export class AppError extends Error {
  constructor(
    message: string,
    public readonly code = "APP_ERROR",
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "AppError";
  }
}

export function getErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }

  return "发生了未知错误，请稍后重试。";
}

export function getAuthErrorMessage(message: string): string {
  const normalized = message.toLowerCase();

  if (normalized.includes("invalid login credentials")) {
    return "邮箱或密码不正确。";
  }

  if (normalized.includes("email not confirmed")) {
    return "请先完成邮箱验证。";
  }

  if (normalized.includes("user already registered")) {
    return "该邮箱已经注册，请直接登录。";
  }

  return message || "认证失败，请稍后重试。";
}
