import { redirect } from "next/navigation";
import { LogOut, ShieldCheck, UsersRound } from "lucide-react";

import { InvitationManager } from "@/components/workspace/invitation-manager";
import { WorkspaceOnboarding } from "@/components/workspace/workspace-onboarding";
import { hasSupabasePublicEnv } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";
import type {
  WorkspaceMembership,
  WorkspaceMemberSummary,
} from "@/types/workspace";

export default async function WorkspacePage({
  searchParams,
}: {
  searchParams: Promise<{ invite?: string }>;
}) {
  if (!hasSupabasePublicEnv()) {
    return <ConfigurationRequired />;
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data, error } = await supabase
    .from("workspace_members")
    .select("workspace_id, role, business_role, workspaces(id, name, timezone)")
    .eq("user_id", user.id)
    .order("joined_at", { ascending: true });

  if (error) {
    return <DatabaseSetupRequired message={error.message} />;
  }

  const memberships = (data ?? []) as unknown as WorkspaceMembership[];
  const params = await searchParams;

  if (memberships.length === 0) {
    return (
      <AppShell email={user.email}>
        <WorkspaceOnboarding initialInvite={params.invite} />
      </AppShell>
    );
  }

  const current = memberships[0];
  const workspace = current.workspaces;
  if (!workspace) return <DatabaseSetupRequired message="工作空间关联数据缺失" />;

  const { data: memberData } = await supabase
    .from("workspace_members")
    .select("user_id, role, business_role, profiles(display_name)")
    .eq("workspace_id", workspace.id)
    .order("joined_at", { ascending: true });

  const members = (memberData ?? []) as unknown as WorkspaceMemberSummary[];

  return (
    <AppShell email={user.email}>
      <div className="mx-auto w-full max-w-6xl space-y-6">
        <header className="rounded-3xl border bg-card p-7 shadow-sm">
          <div className="flex flex-col justify-between gap-5 sm:flex-row sm:items-end">
            <div>
              <p className="text-sm font-medium text-muted-foreground">当前工作空间</p>
              <h1 className="mt-2 text-3xl font-semibold tracking-tight">{workspace.name}</h1>
              <p className="mt-2 text-sm text-muted-foreground">
                {workspace.timezone} · {current.role} · 业务职责 {current.business_role}
              </p>
            </div>
            <span className="inline-flex w-fit items-center gap-2 rounded-full bg-emerald-50 px-3 py-1 text-xs font-medium text-emerald-700">
              <ShieldCheck className="size-4" /> RLS 权限模型已配置
            </span>
          </div>
        </header>

        <div className="grid gap-6 lg:grid-cols-[0.8fr_1.2fr]">
          <section className="rounded-3xl border bg-card p-6 shadow-sm">
            <div className="flex items-center gap-2">
              <UsersRound className="size-5" />
              <h2 className="text-lg font-semibold">团队成员</h2>
            </div>
            <div className="mt-5 space-y-3">
              {members.map((member) => (
                <div className="flex items-center justify-between rounded-xl border p-3" key={member.user_id}>
                  <div>
                    <p className="text-sm font-medium">{member.profiles?.display_name ?? "团队成员"}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{member.role}</p>
                  </div>
                  <span className="rounded-full bg-muted px-3 py-1 text-xs font-medium">
                    职责 {member.business_role}
                  </span>
                </div>
              ))}
            </div>
          </section>

          {current.role === "owner" ? (
            <InvitationManager workspaceId={workspace.id} />
          ) : (
            <section className="rounded-3xl border bg-card p-6 shadow-sm">
              <h2 className="text-lg font-semibold">成员权限</h2>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">
                你可以访问所属工作空间的数据；邀请和空间设置由 owner 管理。
              </p>
            </section>
          )}
        </div>

        <section className="rounded-3xl border border-dashed bg-muted/30 p-8 text-center">
          <p className="text-sm font-medium">第一阶段基础设施已就绪</p>
          <p className="mt-2 text-sm text-muted-foreground">
            课程、任务、日报和 AI 功能将在后续阶段开发。
          </p>
        </section>
      </div>
    </AppShell>
  );
}

function AppShell({ children, email }: { children: React.ReactNode; email?: string }) {
  return (
    <main className="min-h-screen bg-muted/20">
      <nav className="border-b bg-background/90 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5">
          <div>
            <p className="text-sm font-semibold">Course Studio AI</p>
            <p className="text-xs text-muted-foreground">{email}</p>
          </div>
          <form action="/auth/signout" method="post">
            <button className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-muted-foreground hover:bg-muted hover:text-foreground" type="submit">
              <LogOut className="size-4" />退出
            </button>
          </form>
        </div>
      </nav>
      <div className="px-5 py-10">{children}</div>
    </main>
  );
}

function ConfigurationRequired() {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <div className="max-w-lg rounded-3xl border bg-card p-8 shadow-sm">
        <p className="text-sm font-medium text-amber-700">等待 Supabase 配置</p>
        <h1 className="mt-2 text-2xl font-semibold">应用基础已经就绪</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">
          复制 <code>.env.example</code> 为 <code>.env.local</code>，填入 Supabase URL 和 Publishable Key 后重启。
        </p>
      </div>
    </main>
  );
}

function DatabaseSetupRequired({ message }: { message: string }) {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <div className="max-w-lg rounded-3xl border bg-card p-8 shadow-sm">
        <p className="text-sm font-medium text-amber-700">等待数据库迁移</p>
        <h1 className="mt-2 text-2xl font-semibold">请先应用 Supabase migration</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">
          环境已经连接，但身份权限表尚不可用。请应用 <code>supabase/migrations</code> 中的迁移。
        </p>
        <details className="mt-4 text-xs text-muted-foreground">
          <summary>技术信息</summary>
          <pre className="mt-2 overflow-auto whitespace-pre-wrap">{message}</pre>
        </details>
      </div>
    </main>
  );
}
