"use client";

import { Button } from "@/components/ui/button";

export default function ErrorPage({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <div className="max-w-md rounded-3xl border bg-card p-8 text-center shadow-sm">
        <p className="text-sm font-medium text-destructive">页面出现问题</p>
        <h1 className="mt-2 text-2xl font-semibold">暂时无法完成这次操作</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">
          请重试。如果问题持续，请检查环境变量和 Supabase 配置。
        </p>
        <Button className="mt-6" onClick={reset}>重试</Button>
      </div>
    </main>
  );
}
