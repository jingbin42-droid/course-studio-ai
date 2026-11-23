const DEFAULT_AUTH_REDIRECT = "/app";

export function getSafeNextPath(value: string | null | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return DEFAULT_AUTH_REDIRECT;
  }

  try {
    const parsed = new URL(value, "http://course-studio.local");
    if (parsed.origin !== "http://course-studio.local") {
      return DEFAULT_AUTH_REDIRECT;
    }

    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return DEFAULT_AUTH_REDIRECT;
  }
}
