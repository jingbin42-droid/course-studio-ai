"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle, Plus, TicketCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { getErrorMessage } from "@/lib/errors";
import { createClient } from "@/lib/supabase/client";
import type { BusinessRole } from "@/lib/permissions";

export function WorkspaceOnboarding({ initialInvite }: { initialInvite?: string }) {
  const router = useRouter();
  const detectedTimezone = useMemo(
    () => Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
    [],
  );
  const [pending, setPending] = useState<"create" | "join" | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function createWorkspace(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending("create");
    setError(null);

    const data = new FormData(event.currentTarget);
    const supabase = createClient();
    const { error: rpcError } = await supabase.rpc("create_workspace", {
      workspace_name: String(data.get("name") ?? ""),
      workspace_timezone: String(data.get("timezone") ?? detectedTimezone),
      member_business_role: String(data.get("businessRole") ?? "A") as BusinessRole,
    });

    if (rpcError) {
      setError(getErrorMessage(rpcError));
      setPending(null);
      return;
    }

    router.refresh();
  }

  async function joinWorkspace(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending("join");
    setError(null);

    const data = new FormData(event.currentTarget);
    const token = String(data.get("token") ?? "").trim();
    const supabase = createClient();
    const { error: rpcError } = await supabase.rpc("accept_workspace_invitation", {
      invitation_token: token,
    });

    if (rpcError) {
      setError(getErrorMessage(rpcError));
      setPending(null);
      return;
    }

    router.replace("/app");
    router.refresh();
  }

  return (
    <div className="mx-auto w-full max-w-5xl space-y-8">
      <header>
        <p className="text-sm font-medium text-muted-foreground">首次设置</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight">进入团队工作空间</h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-muted-foreground">
          第一位成员创建工作空间并成为 owner；另外两位成员使用邀请令牌加入。
        </p>
      </header>

      {error ? (
        <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive" role="alert">
          {error}
        </div>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="rounded-3xl border bg-card p-6 shadow-sm">
          <div className="mb-6 flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground">
            <Plus className="size-5" />
          </div>
          <h2 className="text-xl font-semibold">创建工作空间</h2>
          <p className="mt-2 text-sm text-muted-foreground">创建者将成为 owner。</p>

          <form className="mt-6 space-y-4" onSubmit={createWorkspace}>
            <Field label="工作空间名称" name="name" placeholder="例如：Course Studio AI 团队" required />
            <Field label="团队时区" name="timezone" defaultValue={detectedTimezone} required />
            <RoleSelect />
            <Button className="h-11 w-full" disabled={pending !== null} type="submit">
              {pending === "create" ? <LoaderCircle className="animate-spin" /> : null}
              创建并进入
            </Button>
          </form>
        </section>

        <section className="rounded-3xl border bg-card p-6 shadow-sm">
          <div className="mb-6 flex size-10 items-center justify-center rounded-xl bg-secondary text-secondary-foreground">
            <TicketCheck className="size-5" />
          </div>
          <h2 className="text-xl font-semibold">加入工作空间</h2>
          <p className="mt-2 text-sm text-muted-foreground">粘贴 owner 分享的邀请令牌。</p>

          <form className="mt-6 space-y-4" onSubmit={joinWorkspace}>
            <Field
              label="邀请令牌"
              name="token"
              defaultValue={initialInvite}
              placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
              required
            />
            <Button className="h-11 w-full" disabled={pending !== null} type="submit" variant="secondary">
              {pending === "join" ? <LoaderCircle className="animate-spin" /> : null}
              加入团队
            </Button>
          </form>
        </section>
      </div>
    </div>
  );
}

function Field({ label, ...props }: React.InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return (
    <label className="block space-y-2 text-sm font-medium">
      <span>{label}</span>
      <input
        className="h-11 w-full rounded-xl border bg-background px-3 outline-none focus:border-ring focus:ring-3 focus:ring-ring/20"
        {...props}
      />
    </label>
  );
}

function RoleSelect() {
  return (
    <label className="block space-y-2 text-sm font-medium">
      <span>我的业务职责</span>
      <select
        className="h-11 w-full rounded-xl border bg-background px-3 outline-none focus:border-ring focus:ring-3 focus:ring-ring/20"
        name="businessRole"
        defaultValue="A"
      >
        <option value="A">A · 课程制作</option>
        <option value="B">B · 宣传与视觉</option>
        <option value="C">C · 上线与运营</option>
      </select>
    </label>
  );
}
