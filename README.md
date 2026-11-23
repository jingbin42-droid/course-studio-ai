# Course Studio AI

Course Studio AI 是面向三人 AI 课程创作与销售团队的“AI 课程团队工作与经营中枢”，采用一个课程项目、团队工作与课程经营两个闭环，以及一个 AI 全能合伙人。

> 当前状态：第一阶段基础设施与身份权限已实现。课程、任务、日报和 AI 业务功能尚未开始。

## 团队角色

| 角色 | 主要职责 |
| --- | --- |
| A | 课程制作、脚本、录课、剪辑 |
| B | 宣传海报、视觉设计、文案、短视频 |
| C | 课程上线、内容发布、运营 |

三个人围绕同一门课程协作。系统不按部门割裂信息，也不按传统 CRM 的客户与商机组织工作。

## 产品核心

- 今日工作台：聚合今日重点、待处理交接、阻塞和课程风险。
- 统一课程项目：从选题到制作、宣传、上线、运营，全程共享上下文。
- 轻量工作记录：成员用自然语言记录完成事项、问题和下一步。
- AI 日报与规划：生成个人日报、团队日报及可确认的明日计划。
- AI 全能合伙人：基于项目事实、团队知识和职责边界提供建议。
- 团队知识库：沉淀课程方法、模板、品牌规范、发布清单和复盘经验。
- 交接与依赖：明确交付物、接收人、验收状态及上下游等待关系。

## 规划文档

- [产品需求文档](docs/PRD.md)
- [系统架构](docs/ARCHITECTURE.md)
- [数据库设计](docs/DATABASE.md)
- [团队工作流](docs/WORKFLOW.md)
- [AI 设计](docs/AI_DESIGN.md)
- [开发路线图](docs/ROADMAP.md)
- [仓库协作规则](AGENTS.md)

## 技术方向

当前基础使用 Next.js 16、TypeScript、Tailwind CSS、shadcn/ui、Supabase 和 Vitest。OpenAI API 保留为后续阶段的服务端能力。

## 第一阶段已包含

- 邮箱密码登录、注册和退出。
- `workspaces`、`profiles`、`workspace_members`、`workspace_invitations`。
- owner/member 权限和 A/B/C 业务职责。
- 创建工作空间、生成邀请链接和接受邀请。
- Supabase 浏览器、服务端和可信服务端客户端边界。
- RLS、RPC、migration、基础错误处理和测试框架。

## Windows 本地启动

要求：Node.js 20.9+ 和 pnpm 11+。

```powershell
pnpm install
Copy-Item .env.example .env.local
pnpm dev
```

然后打开 [http://localhost:3000](http://localhost:3000)。未配置 Supabase 时仍可看到登录页面和配置提示。

## Supabase 配置

1. 创建 Supabase 项目。
2. 按顺序应用 `supabase/migrations` 中的 SQL。
3. 在 Supabase Auth 中配置本地回调地址：`http://localhost:3000/auth/callback`。
4. 将 `.env.example` 复制为 `.env.local`，填入项目 URL 和 Publishable Key。
5. Secret Key 和 `OPENAI_API_KEY` 只能放在服务端环境，不得使用 `NEXT_PUBLIC_` 前缀。

`.env.local` 已被 Git 忽略；`.env.example` 只包含占位符。

| 变量 | 第一阶段是否必需 | 使用位置 |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | 是 | 浏览器与普通服务端 Supabase 客户端 |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | 是 | 浏览器与普通服务端 Supabase 客户端 |
| `SUPABASE_URL` | 仅使用可信管理客户端时 | 可信服务端 |
| `SUPABASE_SECRET_KEY` | 仅使用可信管理客户端时 | 可信服务端，绝不公开 |
| `OPENAI_API_KEY` | 否，后续 AI 阶段使用 | 可信服务端，绝不公开 |
| `NEXT_PUBLIC_APP_URL` | 本地已有默认示例 | 应用地址与回调配置 |

owner 生成邀请链接后，受邀成员应使用邀请邮箱注册或登录。系统会保留邀请令牌，成员确认加入后以 `member` 身份进入同一工作空间。

## 质量检查

```powershell
pnpm lint
pnpm typecheck
pnpm test:run
pnpm build
```

## 当前阶段边界

本阶段不包含课程项目业务、任务管理、工作交接业务、每日记录、日报、AI、pgvector、Cron 或自动化工作流。第一阶段验收后再进入后续开发。
