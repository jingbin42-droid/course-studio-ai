"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle } from "lucide-react";

import { Button } from "@/components/ui/button";
import { getAuthErrorMessage } from "@/lib/errors";
import { createClient } from "@/lib/supabase/client";

export function AuthForm({
  configured,
  nextPath,
}: {
  configured: boolean;
  nextPath: string;
}) {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!configured) return;

    setPending(true);
    setMessage(null);
    setError(null);

    const formData = new FormData(event.currentTarget);
    const email = String(formData.get("email") ?? "").trim();
    const password = String(formData.get("password") ?? "");
    const displayName = String(formData.get("displayName") ?? "").trim();
    const supabase = createClient();

    try {
      if (mode === "register") {
        const { data, error: signUpError } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(nextPath)}`,
            data: { display_name: displayName || email.split("@")[0] },
          },
        });

        if (signUpError) throw signUpError;

        if (!data.session) {
          setMessage("注册成功，请检查邮箱完成验证后登录。");
          return;
        }
      } else {
        const { error: signInError } = await supabase.auth.signInWithPassword({
          email,
          password,
        });

        if (signInError) throw signInError;
      }

      router.replace(nextPath);
      router.refresh();
    } catch (caughtError) {
      const rawMessage =
        caughtError instanceof Error ? caughtError.message : "认证失败";
      setError(getAuthErrorMessage(rawMessage));
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="rounded-3xl border bg-card p-7 shadow-sm sm:p-9">
      <div className="mb-7">
        <p className="text-sm font-medium text-muted-foreground">安全进入团队空间</p>
        <h2 className="mt-2 text-2xl font-semibold tracking-tight">
          {mode === "login" ? "欢迎回来" : "创建成员账号"}
        </h2>
      </div>

      {!configured ? (
        <div className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm leading-6 text-amber-950">
          Supabase 尚未配置。请复制 <code>.env.example</code> 为 <code>.env.local</code>，
          填入项目 URL 和 Publishable Key 后重启开发服务器。
        </div>
      ) : null}

      <form className="space-y-5" onSubmit={handleSubmit}>
        {mode === "register" ? (
          <Field label="显示名称" name="displayName" type="text" autoComplete="name" required />
        ) : null}
        <Field label="邮箱" name="email" type="email" autoComplete="email" required />
        <Field
          label="密码"
          name="password"
          type="password"
          autoComplete={mode === "login" ? "current-password" : "new-password"}
          minLength={8}
          required
        />

        {error ? <p className="text-sm text-destructive" role="alert">{error}</p> : null}
        {message ? <p className="text-sm text-emerald-700" role="status">{message}</p> : null}

        <Button className="h-11 w-full" disabled={!configured || pending} type="submit">
          {pending ? <LoaderCircle className="animate-spin" /> : null}
          {mode === "login" ? "登录" : "注册"}
        </Button>
      </form>

      <button
        className="mt-6 w-full text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
        type="button"
        onClick={() => {
          setMode((current) => (current === "login" ? "register" : "login"));
          setError(null);
          setMessage(null);
        }}
      >
        {mode === "login" ? "还没有账号？创建成员账号" : "已有账号？返回登录"}
      </button>
    </div>
  );
}

function Field({ label, ...props }: React.InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return (
    <label className="block space-y-2 text-sm font-medium">
      <span>{label}</span>
      <input
        className="h-11 w-full rounded-xl border bg-background px-3 outline-none transition focus:border-ring focus:ring-3 focus:ring-ring/20"
        {...props}
      />
    </label>
  );
}
