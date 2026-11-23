import Link from "next/link";

import { Button } from "@/components/ui/button";

export default function NotFound() {
  return (
    <main className="grid min-h-screen place-items-center p-6 text-center">
      <div>
        <p className="text-sm font-medium text-muted-foreground">404</p>
        <h1 className="mt-2 text-3xl font-semibold">页面不存在</h1>
        <Button className="mt-6" render={<Link href="/app" />}>返回工作空间</Button>
      </div>
    </main>
  );
}
