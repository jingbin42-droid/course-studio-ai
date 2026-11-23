import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Course Studio AI",
  description: "AI 课程团队工作与经营中枢",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
