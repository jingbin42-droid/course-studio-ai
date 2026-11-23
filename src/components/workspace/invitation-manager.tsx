"use client";

import { useState, type FormEvent } from "react";
import { Copy, LoaderCircle } from "lucide-react";

import { Button } from "@/components/ui/button";
import { getErrorMessage } from "@/lib/errors";
import { createClient } from "@/lib/supabase/client";
import type { BusinessRole } from "@/lib/permissions";

export function InvitationManager({ workspaceId }: { workspaceId: string }) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [invitationLink, setInvitationLink] = useState<string | null>(null);

  async function createInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setInvitationLink(null);

    const data = new FormData(event.currentTarget);
    const supabase = createClient();
    const { data: token, error: rpcError } = await supabase.rpc(
      "create_workspace_invitation",
      {
        target_workspace_id: workspaceId,
        invitee_email: String(data.get("email") ?? ""),
        invitee_business_role: String(data.get("businessRole") ?? "B") as BusinessRole,
      },
    );

    if (rpcError || !token) {
      setError(getErrorMessage(rpcError ?? new Error("未生成邀请令牌")));
      setPending(false);
      return;
    }

    setInvitationLink(`${window.location.origin}/app?invite=${token}`);
    setPending(false);
    event.currentTarget.reset();
  }

  async function copyLink() {
    if (invitationLink) await navigator.clipboard.writeText(invitationLink);
  }

  return (
    <section className="rounded-3xl border bg-card p-6 shadow-sm">
      <h2 className="text-lg font-semibold">邀请团队成员</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        创建邀请链接后，通过可信渠道发送给对应成员。
      </p>

      <form className="mt-5 grid gap-3 sm:grid-cols-[1fr_180px_auto]" onSubmit={createInvitation}>
        <input
          className="h-10 rounded-xl border bg-background px-3 text-sm outline-none focus:border-ring focus:ring-3 focus:ring-ring/20"
          name="email"
          type="email"
          placeholder="成员邮箱"
          required
        />
        <select className="h-10 rounded-xl border bg-background px-3 text-sm" name="businessRole" defaultValue="B">
          <option value="A">A · 课程制作</option>
          <option value="B">B · 宣传与视觉</option>
          <option value="C">C · 上线与运营</option>
        </select>
        <Button className="h-10" disabled={pending} type="submit">
          {pending ? <LoaderCircle className="animate-spin" /> : null}
          生成邀请
        </Button>
      </form>

      {error ? <p className="mt-3 text-sm text-destructive" role="alert">{error}</p> : null}
      {invitationLink ? (
        <div className="mt-4 flex items-center gap-2 rounded-xl bg-muted p-3">
          <code className="min-w-0 flex-1 truncate text-xs">{invitationLink}</code>
          <Button aria-label="复制邀请链接" onClick={copyLink} size="icon" variant="ghost">
            <Copy />
          </Button>
        </div>
      ) : null}
    </section>
  );
}
