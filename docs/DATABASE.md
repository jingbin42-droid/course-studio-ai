# Course Studio AI 数据库设计

## 1. 设计原则

数据库以课程协作为中心，而不是以客户关系为中心。

- 一个 `course_project` 同时承载团队工作闭环和课程经营闭环，不复制为两套项目数据。
- PostgreSQL 是业务事实的唯一主存储。
- 原始工作记录与 AI 派生内容分开保存。
- 任务、依赖和交接分别建模，避免语义混淆。
- AI 建议不直接成为正式事实，必须有草稿状态和确认人。
- 核心历史通过事件或版本快照保留。
- MVP 字段保持克制；只有高频查询或关键规则使用独立字段。
- 经营数据必须来自人工录入或已确认来源；未知值使用 `NULL`，不得用 0 或 AI 推测补齐。

以下是逻辑设计，具体 SQL、枚举实现方式和迁移将在开发阶段确认。

## 2. 核心关系

```text
workspaces ──< workspace_members >── profiles
  │
  ├──< workspace_invitations
  │
  ├──< course_projects ──< milestones
  │          │
  │          ├──< work_items ──< work_item_dependencies
  │          │        └──< handoffs ──< handoff_events
  │          │
  │          ├──< work_logs
  │          ├──< project_assets（P1）
  │          └──< project_events
  │
  ├──< daily_reports
  ├──< knowledge_entries（P1）
  ├──< course_operation_metrics（P1）
  └──< ai_artifacts ──< ai_source_links
```

大多数业务表带 `workspace_id`。同时带父实体 ID 是为了表达关系；`workspace_id` 便于 RLS 和高频过滤，但写入时必须校验与父实体工作空间一致。

## 3. 身份与团队

### 3.1 `profiles`

对应 Supabase Auth 用户的公开业务资料。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 对应 `auth.users.id` |
| `display_name` | text | 显示名 |
| `avatar_url` | text nullable | 头像 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

团队业务时间不使用个人资料字段，以 `workspaces.timezone` 为唯一口径。

### 3.2 `workspaces`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 团队 ID |
| `name` | text | 团队名称 |
| `timezone` | text | IANA 时区，由创建者设置；可建议但不能固定为 `Asia/Shanghai` |
| `created_by` | uuid FK | 创建团队的 owner |
| `created_at` | timestamptz | 创建时间 |

### 3.3 `workspace_members`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `workspace_id` | uuid FK | 所属工作空间 |
| `user_id` | uuid FK | 成员 |
| `team_role` | text | `owner` / `member` |
| `work_role` | text | `A` / `B` / `C`；业务职责标识 |
| `is_active` | boolean | 是否有效成员 |
| `joined_at` | timestamptz | 加入时间 |

约束：`(workspace_id, user_id)` 唯一；同一活跃工作空间的 `work_role` 在 MVP 中建议唯一，但不把它做成长期不可变规则。

`team_role` 与 `work_role` 语义独立：`owner` / `member` 控制团队管理权限，A/B/C 只表达业务职责。首位创建团队的用户写入为 `owner`；接受邀请的另外两人写入为 `member`。

### 3.4 `workspace_invitations`

用于把另外两名成员安全地关联到同一团队，不替代 Supabase Auth 的身份认证。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 邀请 ID |
| `workspace_id` | uuid FK | 目标工作空间 |
| `email` | text | 受邀邮箱，规范化后比较 |
| `team_role` | text | MVP 固定为 `member` |
| `work_role` | text | 预设 `A` / `B` / `C` 业务职责 |
| `status` | text | `pending` / `accepted` / `revoked` / `expired` |
| `invited_by` | uuid FK | 必须是团队 owner |
| `accepted_by` | uuid FK nullable | 接受邀请的登录用户 |
| `expires_at` | timestamptz nullable | 可选过期时间 |
| `accepted_at` | timestamptz nullable | 接受时间 |
| `created_at` | timestamptz | 创建时间 |

接受邀请时以一次事务校验邮箱、邀请状态和工作空间，创建 `workspace_members` 记录并把邀请标记为 `accepted`。同一工作空间的有效待接受邮箱邀请应唯一。

## 4. 课程项目

### 4.1 `course_projects`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 课程项目 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `title` | text | 课程名称 |
| `summary` | text nullable | 简介 |
| `audience` | text nullable | 目标学员 |
| `core_promise` | text nullable | 课程核心承诺/价值 |
| `stage` | text | `idea` / `planning` / `production` / `promotion` / `launch` / `operation` / `archived` |
| `owner_id` | uuid FK | 项目负责人 |
| `target_launch_at` | timestamptz nullable | 目标上线时间 |
| `target_sales_at` | timestamptz nullable | 目标正式销售时间，可晚于上线时间 |
| `health` | text | `on_track` / `at_risk` / `off_track`；可由人确认或规则建议 |
| `created_by` | uuid FK | 创建人 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |
| `archived_at` | timestamptz nullable | 归档时间 |

`health` 不是 AI 可静默修改的事实。AI 可以提出风险建议，由负责人确认，或采用透明的确定性规则计算展示。

首页的上线/销售缺口从里程碑、未完成工作项、依赖和未验收交接推导。没有足够事实时展示未知或待补充，不生成虚构完成率。

### 4.2 `milestones`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 里程碑 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK | 所属课程 |
| `title` | text | 如“完成录制”“课程上线” |
| `due_at` | timestamptz nullable | 目标时间 |
| `status` | text | `planned` / `achieved` / `missed` / `cancelled` |
| `achieved_at` | timestamptz nullable | 达成时间 |
| `created_by` | uuid FK | 创建人 |

MVP 使用显式里程碑，不构建甘特图或复杂排期算法。

## 5. 工作项、依赖与交接

### 5.1 `work_items`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 工作项 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK | 所属课程 |
| `milestone_id` | uuid FK nullable | 可选里程碑 |
| `title` | text | 标题 |
| `description` | text nullable | 说明与完成标准 |
| `workstream` | text | `production` / `promotion` / `operation` / `shared` |
| `status` | text | `backlog` / `ready` / `in_progress` / `blocked` / `review` / `done` / `cancelled` |
| `priority` | text | `low` / `medium` / `high` / `urgent` |
| `assignee_id` | uuid FK nullable | 负责人 |
| `due_at` | timestamptz nullable | 截止时间 |
| `blocked_reason` | text nullable | 当前阻塞原因 |
| `completed_at` | timestamptz nullable | 完成时间 |
| `created_by` | uuid FK | 创建人 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

MVP 每个工作项只设一位负责人，以确保责任明确；协作者通过工作记录、交接和后续工作项表达。

### 5.2 `work_item_dependencies`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `work_item_id` | uuid FK | 被阻塞/下游工作项 |
| `depends_on_work_item_id` | uuid FK | 前置工作项 |
| `dependency_type` | text | MVP 固定为 `finish_to_start`，预留扩展 |
| `created_by` | uuid FK | 创建人 |
| `created_at` | timestamptz | 创建时间 |

约束：两个 ID 不得相同；组合唯一；应用层在写入前检测循环依赖。前置任务完成后，系统只提示“依赖已解除”，不自动把下游状态改为进行中。

### 5.3 `handoffs`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 交接 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK | 所属课程 |
| `work_item_id` | uuid FK | 关联交付任务 |
| `from_user_id` | uuid FK | 交付人 |
| `to_user_id` | uuid FK | 接收人 |
| `title` | text | 交接标题 |
| `note` | text nullable | 使用说明、版本、注意事项 |
| `deliverable_url` | text nullable | 当前版本产出链接；P0 可仅用链接 |
| `current_revision` | integer | 当前修订号，首次提交为 1 |
| `status` | text | `submitted` / `received` / `changes_requested` / `accepted` / `cancelled` |
| `submitted_at` | timestamptz | 提交时间 |
| `responded_at` | timestamptz nullable | 最近响应时间 |
| `response_note` | text nullable | 接收反馈 |
| `updated_at` | timestamptz | 最近状态或版本更新时间 |

`handoffs` 只保存当前快照，所有提交和反馈历史必须写入 `handoff_events`。重新提交时更新当前链接和修订号，将当前状态恢复为 `submitted`，但不得删除或覆盖旧事件。

### 5.4 `handoff_events`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 事件 ID |
| `workspace_id` | uuid FK | 所属工作空间，必须与交接一致 |
| `handoff_id` | uuid FK | 所属交接 |
| `actor_id` | uuid FK | 执行提交或反馈的成员 |
| `event_type` | text | `submitted` / `received` / `changes_requested` / `resubmitted` / `accepted` / `cancelled` |
| `revision` | integer | 该事件对应的交付修订号 |
| `deliverable_url` | text nullable | 该修订版本的产出链接 |
| `note` | text nullable | 提交说明、修改反馈、验收或取消原因 |
| `created_at` | timestamptz | 事件发生时间，不允许覆盖更新 |

首次提交写入 `submitted`；每次要求修改和重新提交分别追加事件。`changes_requested` 与 `resubmitted` 可重复循环，直到 `accepted` 或 `cancelled`，从而保留所有历史反馈。

## 6. 工作记录与事件

### 6.1 `work_logs`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 记录 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `author_id` | uuid FK | 记录人 |
| `course_project_id` | uuid FK nullable | 用户确认或 AI 建议关联的课程 |
| `work_item_id` | uuid FK nullable | 可选关联工作项 |
| `raw_text` | text | 用户原始自然语言记录 |
| `log_date` | date | 按团队时区确定的业务日期 |
| `visibility` | text | `team` / `private`，默认 `team` |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

`log_date` 实际按团队时区形成团队业务日期，不使用成员个人时区。原文允许作者编辑，但应保留 `updated_at`；若后续需要严格审计，再引入版本表。AI 提取结果不直接写回 `raw_text`。

当 `visibility = private` 时，只有 `author_id = auth.uid()` 可以读取；团队其他成员、团队日报查询和由其他成员发起的 AI 请求都不能读取该记录。

### 6.2 `project_events`

统一保存对动态、日报和审计有价值的业务事件。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 事件 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK nullable | 关联课程 |
| `actor_id` | uuid FK nullable | 操作者；系统事件可空 |
| `event_type` | text | 如 `work_item.status_changed`、`handoff.accepted` |
| `entity_type` | text | 实体类型 |
| `entity_id` | uuid | 实体 ID |
| `payload` | jsonb | 仅保存事件必要的前后值或补充信息 |
| `occurred_at` | timestamptz | 发生时间 |

`payload` 用于事件差异，不替代实体的可查询字段。

## 7. 日报与明日计划

### 7.1 `daily_reports`

个人日报、团队日报和明日计划共享可审计的文档模型。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 报告 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `report_type` | text | `personal_daily` / `team_daily` / `tomorrow_plan` |
| `report_date` | date | 团队业务日期；明日计划表示计划执行日 |
| `subject_user_id` | uuid FK nullable | 个人报告对应成员；团队报告为空 |
| `content` | jsonb | 经过模式校验的结构化内容 |
| `rendered_text` | text | 便于编辑和展示的文本快照 |
| `status` | text | `draft` / `accepted` / `edited` / `dismissed` |
| `generated_by_artifact_id` | uuid FK nullable | 对应 AI 生成记录 |
| `confirmed_by` | uuid FK nullable | 确认人 |
| `confirmed_at` | timestamptz nullable | 确认时间 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

建议唯一性：同一团队、类型、日期和成员可以有多个草稿，但最多一个当前确认版本。具体使用部分唯一索引或版本字段在迁移时实现。

`report_date` 使用团队业务日期。MVP 仅由用户主动触发生成，不建立定时任务。

`tomorrow_plan` 的 `content` 中，每个计划项必须标记一种类型：

- `existing_work_item`：必须包含原 `work_item_id`；
- `new_task_proposal`：确认前没有正式任务，确认创建后记录新 `work_item_id`；
- `advice`：纯建议，不创建任务。

只有 `confirmed_at` 非空，且状态为 `accepted` 或已人工修改确认的计划，才进入对应日期首页。确认计划不得更新 `work_items.due_at`；改期必须作为独立动作校验和确认。团队日报的数据查询显式排除 `work_logs.visibility = private`。

## 8. 课程资产与知识库

### 8.1 `project_assets`（P1）

P1 可增加轻量资产索引，不替代网盘或专业制作工具。MVP 使用交接中的产出链接、版本和事件历史满足协作需要。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 资产 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK | 所属课程 |
| `title` | text | 资产名称 |
| `asset_type` | text | `script` / `video` / `image` / `copy` / `document` / `link` / `other` |
| `url` | text | 外部链接或后续的 Storage URL |
| `version_label` | text nullable | 人类可读版本，如 `v2-final` |
| `status` | text | `draft` / `review` / `approved` / `archived` |
| `created_by` | uuid FK | 创建人 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

### 8.2 `knowledge_entries`（P1）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 知识条目 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK nullable | 课程专属知识可关联课程 |
| `title` | text | 标题 |
| `content` | text | 正文 |
| `source_url` | text nullable | 外部来源 |
| `category` | text | `template` / `brand` / `checklist` / `channel` / `decision` / `retrospective` / `other` |
| `tags` | text[] | 轻量标签 |
| `metadata` | jsonb | 分类专用的轻量结构化信息 |
| `status` | text | `draft` / `verified` / `archived` |
| `owner_id` | uuid FK | 维护人 |
| `created_by` | uuid FK | 创建人 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

当 `category = decision` 时，`content` 保存决策内容，`metadata` 使用固定结构保存 `reason`、`participant_user_ids`、`impact_scope`、`related_work_item_ids` 和 `follow_up`。服务端校验参与成员和关联工作项属于同一团队。P1 使用该分类实现团队决策记忆，不创建独立决策表或审批流。

### 8.3 `course_operation_metrics`（P1）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | 指标记录 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `course_project_id` | uuid FK | 所属课程 |
| `metric_date` | date | 团队业务日期 |
| `channel` | text | 渠道名称 |
| `impressions` | bigint nullable | 曝光 |
| `clicks` | bigint nullable | 点击 |
| `inquiries` | bigint nullable | 咨询数量，仅聚合值 |
| `orders` | bigint nullable | 订单数量，仅聚合值 |
| `revenue_amount` | numeric nullable | 销售额 |
| `currency` | text nullable | ISO 货币代码 |
| `review_note` | text nullable | 宣传效果复盘 |
| `source_note` | text nullable | 数据来源说明，不保存个人明细 |
| `source_type` | text | `manual` / `confirmed_import`；P1 默认手工录入 |
| `created_by` | uuid FK | 记录人 |
| `created_at` | timestamptz | 创建时间 |
| `updated_at` | timestamptz | 更新时间 |

该表同时承载渠道经营数据和聚合销售结果。数量与金额字段必须为非负值；未知值保持 `NULL`，不能转换为 0。填写销售额时应提供货币代码。该表禁止保存客户姓名、电话、账号、聊天记录、单笔订单或其他个人明细，不建设客户、线索、合同、收款、成本核算或复杂财务账务。

宣传效果复盘保存为 `review_note`，或进一步沉淀到 `knowledge_entries(category = retrospective)`。知识库向量检索暂不进入 MVP 或 P1，因此当前不建立 `knowledge_chunks` 表。

## 9. AI 产物与来源

### 9.1 `ai_artifacts`

统一记录一次 AI 产物或动作建议。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | uuid PK | AI 产物 ID |
| `workspace_id` | uuid FK | 所属工作空间 |
| `created_by` | uuid FK | 发起人 |
| `course_project_id` | uuid FK nullable | 关联课程 |
| `artifact_type` | text | `work_log_parse` / `daily_report` / `tomorrow_plan` / `partner_answer` / `promotion_draft` / `action_proposal` / `business_analysis` |
| `prompt_version` | text | 提示版本 |
| `model` | text | 实际模型标识 |
| `input_summary` | jsonb | 最小必要的输入元数据，不默认复制全部正文 |
| `output` | jsonb | 经模式校验的输出 |
| `status` | text | `draft` / `accepted` / `edited` / `dismissed` / `failed` |
| `error_code` | text nullable | 失败分类 |
| `latency_ms` | integer nullable | 耗时 |
| `usage` | jsonb nullable | token/成本相关元数据 |
| `created_at` | timestamptz | 创建时间 |
| `resolved_at` | timestamptz nullable | 用户处理时间 |

### 9.2 `ai_source_links`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `ai_artifact_id` | uuid FK | AI 产物 |
| `source_type` | text | `work_log` / `work_item` / `event` / `handoff` / `knowledge` / `asset` / `business_metric` |
| `source_id` | uuid | 来源 ID |
| `excerpt` | text nullable | 展示用短摘录，避免重复全文 |
| `relevance` | real nullable | 可选相关度 |

该表支持日报和 AI 回答的来源追溯。应用在展示引用前再次校验当前用户是否仍有权访问来源。

## 10. 评论与通知的取舍

MVP 不建立复杂评论系统。修改反馈使用 `handoff_events.note`，任务说明和工作记录承载必要上下文；未来只有在真实使用证明需要时才评估轻量评论。

MVP 不建立自动通知系统或 `notifications` 表。“待我处理”由首页实时查询；未来只有出现明确站外提醒需求时再评估。

## 11. RLS 策略原则

每张工作空间业务表启用 RLS：

1. `SELECT`：当前 `auth.uid()` 必须是相同 `workspace_id` 的活跃成员。
2. `INSERT`：写入的 `workspace_id` 必须属于当前成员，`created_by` / `author_id` 通常等于当前用户。
3. `UPDATE`：团队成员可按业务规则修改共享数据；私人工作记录和私人草稿只允许作者修改。
4. `DELETE`：尽量使用归档或取消状态；确需删除时限制为创建者或团队 owner，并保留关键事件。
5. 子表如果没有独立 `workspace_id`，必须通过父表进行权限判断；本设计优先保留 `workspace_id` 以简化策略。

RLS 之外，服务端仍需检查状态转换、负责人是否属于团队、父子团队是否一致等业务约束。

邀请数据仅允许团队 owner 查询和管理；受邀用户接受邀请时通过受控服务端流程校验登录邮箱。私人工作记录的 `SELECT` 策略只允许作者本人。任何 AI 数据查询先受相同 RLS 和业务权限约束，不能使用 service-role 绕过权限后再让模型自行过滤。

## 12. 团队时区与业务日期规则

- `workspaces.timezone` 是团队业务时间的唯一来源，使用有效 IANA 时区。
- 某个事件的默认业务日期等于 `occurred_at` / `created_at` 转换到团队时区后的本地日期。
- `work_logs.log_date` 允许补记时明确指定；日报按 `report_date` 聚合业务事实，不直接按数据库 UTC 日期截取。
- 明日计划的 `report_date` 是当前团队业务日期的下一日。
- 团队时区改变只影响后续默认日期计算，不回算已保存的 `log_date`、`report_date` 和 `metric_date`。
- 时间戳继续以 UTC 保存，日期字段保存已经确定的团队业务日期。

## 13. 索引与约束建议

- `workspace_members(workspace_id, user_id)` 唯一索引。
- `workspace_invitations(workspace_id, email)` 对有效待接受邀请建立唯一约束。
- `course_projects(workspace_id, stage, target_launch_at)` 和正式销售目标日期相关索引按首页查询验证后增加。
- `work_items(workspace_id, assignee_id, status, due_at)`。
- `work_items(course_project_id, workstream, status)`。
- `work_item_dependencies(work_item_id, depends_on_work_item_id)` 唯一索引。
- `handoffs(workspace_id, to_user_id, status, submitted_at)`。
- `handoff_events(handoff_id, created_at)`。
- `work_logs(workspace_id, author_id, log_date)`。
- `project_events(course_project_id, occurred_at desc)`。
- `daily_reports(workspace_id, report_date, report_type, subject_user_id)`。
- `knowledge_entries(workspace_id, status, category)`；MVP/P1 不增加向量索引。
- `course_operation_metrics(course_project_id, metric_date, channel)`（P1）。
- 所有枚举值使用 `CHECK` 或 PostgreSQL enum 保证合法；选型在首次迁移前统一。
- 时间字段数据库统一存 UTC，日期归属按成员时区计算。

知识库当前不使用向量索引。`handoff_events` 采用追加写入，不允许普通更新或删除。

## 14. 数据保留与隐私

- 工作记录、日报和项目事件默认保留，归档课程不删除历史。
- AI 失败响应和完整提示是否保存，应在开发前确定最小化策略。
- 删除用户账号前处理其作为负责人、作者和确认人的引用，不能简单级联删除项目历史。
- 向外部模型发送数据前执行权限与最小必要上下文过滤。
- 若未来加入文件，Storage bucket 同样按团队和成员权限配置策略。
- 私人工作记录不得进入团队日报、团队搜索或其他成员的 AI 上下文。
- 运营指标只保存聚合数字和复盘说明，不保存客户个人数据。
- AI 经营分析只能引用已保存的 `course_operation_metrics`；没有记录的指标保持未知。

## 15. 首版迁移建议

为控制风险，按产品阶段建立：

### P0 表

- 身份与团队：`profiles`、`workspaces`、`workspace_members`、`workspace_invitations`。
- 课程与执行：`course_projects`、`milestones`、`work_items`、`work_item_dependencies`、`project_events`。
- 交接与记录：`handoffs`、`handoff_events`、`work_logs`。
- AI 与日报：`ai_artifacts`、`ai_source_links`、`daily_reports`。

### P1 表

- 素材：`project_assets`。
- 知识与决策：`knowledge_entries`，其中 `decision` 分类保存决策记忆。
- 经营与销售结果：`course_operation_metrics`。

### P2 或更后

- 第三方平台集成所需同步记录、自动发布记录和自动化调度数据，在需求确认后再设计。
- 高级知识检索如确有需要，再评估 `knowledge_chunks` 或其他索引；当前不预建。

每一批先用真实课程样例验证查询和 RLS，再增加下一批。以上只是逻辑实施顺序，不代表本轮创建数据库迁移。定时任务、自动通知、复杂评论、`knowledge_chunks` 向量表和多 Agent 执行均不在 MVP/P1 数据范围内。
