import { Bot, ShieldCheck, Users } from "lucide-react";

import { AuthForm } from "@/components/auth/auth-form";
import { hasSupabasePublicEnv } from "@/lib/env";
import { getSafeNextPath } from "@/lib/redirects";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const configured = hasSupabasePublicEnv();
  const params = await searchParams;
  const nextPath = getSafeNextPath(params.next);

  return (
    <main className="grid min-h-screen lg:grid-cols-[1.1fr_0.9fr]">
      <section className="hidden border-r bg-neutral-950 p-12 text-white lg:flex lg:flex-col lg:justify-between">
        <div className="flex items-center gap-3 text-sm font-semibold tracking-wide">
          <span className="grid size-9 place-items-center rounded-xl bg-white text-neutral-950">
            CS
          </span>
          COURSE STUDIO AI
        </div>

        <div className="max-w-xl space-y-8">
          <p className="text-sm font-medium text-neutral-400">一个课程项目 · 两个业务闭环</p>
          <h1 className="text-5xl font-semibold leading-tight tracking-tight">
            AI 课程团队
            <br />
            工作与经营中枢
          </h1>
          <div className="grid gap-4 text-sm text-neutral-300 sm:grid-cols-3">
            <Feature icon={Users} title="三人协作" description="A 制作、B 宣传、C 运营" />
            <Feature icon={ShieldCheck} title="权限隔离" description="工作空间与 RLS 双重保护" />
            <Feature icon={Bot} title="AI 合伙人" description="后续阶段接入真实项目上下文" />
          </div>
        </div>

        <p className="text-xs text-neutral-500">第一阶段 · 基础设施与身份权限</p>
      </section>

      <section className="flex items-center justify-center px-6 py-12">
        <div className="w-full max-w-md">
          <div className="mb-8 lg:hidden">
            <p className="text-sm font-semibold">COURSE STUDIO AI</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight">登录团队工作空间</h1>
          </div>
          <AuthForm configured={configured} nextPath={nextPath} />
        </div>
      </section>
    </main>
  );
}

function Feature({
  icon: Icon,
  title,
  description,
}: {
  icon: typeof Users;
  title: string;
  description: string;
}) {
  return (
    <div className="space-y-2 rounded-2xl border border-white/10 bg-white/5 p-4">
      <Icon className="size-5" aria-hidden="true" />
      <p className="font-medium text-white">{title}</p>
      <p className="leading-5 text-neutral-400">{description}</p>
    </div>
  );
}
