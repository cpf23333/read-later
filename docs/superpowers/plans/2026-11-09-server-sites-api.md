# Server Sites API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 Hono + SQLite 服务器上新增 `/api/sites`（站点收藏，含回收站），现有接口与数据表不改动。

**Architecture:** 新建独立 `sites` 表（软删除字段 `deleted_at` + `url` 唯一索引），在 `utils/database.ts` 增加仓储函数，新建 `routes/sites.ts` 挂到现有 `app.use('/api/*', authMiddleware)` 之后；URL 统一归一化为 origin。移动端 Flutter 计划依赖本计划完成。

**Tech Stack:** Hono 4、better-sqlite3、TypeScript、tsx、Node ≥ 20。

**Spec:** `docs/superpowers/specs/2026-11-09-readlater-mobile-flutter-design.md`（5.4 节为接口契约，15 节为决策）

## Global Constraints

- 只新增 `sites` 表与 `/api/sites` 路由组；不改动 `links`/`trash` 表、不改动任何现有端点与响应格式。
- 所有 `/api/*` 由现有 `authMiddleware` 保护：无 `Authorization: Bearer <API_KEY>` 返回 401（不要在路由内重复实现鉴权）。
- 写操作路由统一加 `apiRateLimit`；错误响应格式 `{ success: false, error: string }`。
- 站点 URL 一律归一化为 origin：`new URL(url).origin`（非法 URL 返回 400）。
- `sites.url` 建唯一索引；重复收藏活跃站点幂等返回已有记录；重复收藏回收站中的站点自动恢复并更新 `title`/`icon_url`。
- 路由注册顺序：`/trash`、`/trash/:id` 必须在 `/:id` 之前，避免 `trash` 被当成 id。
- 所有 id 经 `sanitizeId()` 校验，非法返回 400。
- 站点不落盘图片（只有 `icon_url` 文本），回收站操作不涉及文件系统。

## Review Focus

1. **重复与恢复**：活跃站点重复 POST 返回同一条记录；已在回收站的 URL 再次 POST 必须恢复而不是插入新行（唯一索引冲突最容易在这里出 bug）。
2. **路由顺序**：`GET /api/sites/trash` 不能被 `GET /api/sites/:id` 之类的路由吞掉。
3. **非法 URL**：`not-a-url`、空字符串、`ftp://x` 必须 400，不能写库、不能让服务端 500。
4. **鉴权**：四个新端点无 token 一律 401，且错误体格式与现有接口一致。
5. **永久删除边界**：对活跃站点调用 `DELETE /api/sites/trash/:id` 不能删掉它；对不存在 id 保持幂等成功。

---

### Task 1: sites 数据层与 API

**Files:**
- Create: `server/src/routes/sites.ts`
- Modify: `server/src/types/index.ts`（文件末尾追加 `Site`、`SiteInput`、`SiteExistsResponse`）
- Modify: `server/src/utils/url.ts`（追加 `normalizeOrigin`）
- Modify: `server/src/utils/database.ts`（`initDatabase` 的建表语句后追加 `sites` 表与索引；文件内新增站点仓储函数）
- Modify: `server/src/index.ts`（在 `/api/stats` 挂载之后加一行 `app.route('/api/sites', sitesRoute)`）
- Test: 无自动化测试框架，本任务用 curl 断言（见 Step 4）

**Interfaces:**
- Consumes: `getDatabase()`、`sanitizeId()`、`apiRateLimit`、`ApiResponse<T>`、`normalizeUrl()`。
- Produces:
  - `interface Site { id: string; url: string; title: string; icon_url: string | null; created_at: number; deleted_at: number | null }`
  - `interface SiteInput { url: string; title?: string; icon_url?: string }`
  - `interface SiteExistsResponse { exists: boolean; inTrash: boolean }`
  - `normalizeOrigin(url: string): string | null`
  - `addSite(input: { id?: string; url: string; title: string; icon_url: string | null }): Site`
  - `getSiteById(id: string): Site | undefined`
  - `getSiteByOrigin(origin: string): Site | undefined`
  - `getSites(): Site[]`
  - `getSiteTrash(): Site[]`
  - `reviveSite(site: Site, title: string, icon_url: string | null): Site`
  - `softDeleteSite(id: string): void`
  - `restoreSite(id: string): void`
  - `deleteSitePermanently(id: string): void`
  - 端点：`GET /api/sites`、`POST /api/sites`、`DELETE /api/sites/:id`、`GET /api/sites/trash`、`POST /api/sites/:id/restore`、`DELETE /api/sites/trash/:id`、`GET /api/sites/exists`。

- [ ] **Step 1: 写类型与 normalizeOrigin**

`server/src/utils/url.ts` 追加：

```ts
export function normalizeOrigin(url: string): string | null {
  try {
    const u = new URL(url);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    return u.origin;
  } catch {
    return null;
  }
}
```

`server/src/types/index.ts` 追加三个接口（字段名与 `Site` 上表完全一致，`deleted_at` 为 `number | null`）。

- [ ] **Step 2: 建表与仓储函数**

`initDatabase()` 的 `db.exec(...)` 建表块内追加：

```sql
CREATE TABLE IF NOT EXISTS sites (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  title TEXT,
  icon_url TEXT,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_url ON sites(url);
CREATE INDEX IF NOT EXISTS idx_sites_deleted ON sites(deleted_at);
```

仓储函数行为（SQL 用预编译语句，参照现有 `addLink`/`getTrashItems` 的写法）：

- `addSite`：`INSERT`，`url` 调用方已归一化；`id` 未传时按现有 `addLink` 同样的规则生成（`Date.now()_随机串`）；`created_at` 用 `Date.now()`。
- `reviveSite`：`UPDATE sites SET deleted_at = NULL, title = ?, icon_url = ? WHERE id = ?`，返回更新后的记录。
- `softDeleteSite`：`UPDATE sites SET deleted_at = ? WHERE id = ?`（当前时间）。
- `restoreSite`：`UPDATE sites SET deleted_at = NULL WHERE id = ?`。
- `deleteSitePermanently`：`DELETE FROM sites WHERE id = ? AND deleted_at IS NOT NULL`。
- `getSites`：`WHERE deleted_at IS NULL ORDER BY created_at DESC`。
- `getSiteTrash`：`WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC`。

- [ ] **Step 3: 实现路由**

`server/src/routes/sites.ts` 新建 `const app = new Hono()`，按以下顺序注册（顺序即约束）：

1. `GET /trash` → `{ success: true, data: Site[] }`
2. `POST /trash` 不实现（无该需求），跳过
3. `DELETE /trash/:id` → 永久删除；`sanitizeId` 失败 400；不存在也返回 `{ success: true }`
4. `GET /exists` → `url` 查询参数；`normalizeOrigin` 为 null 返回 400；用 `getSiteByOrigin` 判断 `exists`（active）与 `inTrash`（记录存在但 `deleted_at` 非空）
5. `GET /` → `{ success: true, data: getSites() }`
6. `POST /` → 解析 `{ url, title?, icon_url? }`；`normalizeOrigin` 失败 400；若已存在：`deleted_at == null` 直接返回已有记录，否则 `reviveSite` 并返回；不存在则 `addSite` 后返回 `{ success: true, data: site }`（HTTP 200）
7. `DELETE /:id` → 软删除，返回 `{ success: true }`
8. `POST /:id/restore` → `sanitizeId`；不存在或不在回收站返回 404；否则 `restoreSite` 返回 `{ success: true }`

每个写端点挂 `apiRateLimit`。`server/src/index.ts` 引入 `sitesRoute` 并在 `app.route('/api/stats', statsRoute)` 后挂载。

- [ ] **Step 4: 启动服务器并跑 curl 断言**

```bash
cd server
pnpm typecheck
$env:API_KEY='test-key'; $env:PORT='3999'; $env:DATA_DIR='./.tmp-sites-test'; pnpm dev
```

另一个终端（Windows PowerShell）：

```powershell
$h = @{ Authorization = 'Bearer test-key'; 'Content-Type' = 'application/json' }
$base = 'http://127.0.0.1:3999/api/sites'
# 1) 新增：url 归一化为 origin
curl.exe -s -X POST $base -H "Authorization: Bearer test-key" -H "Content-Type: application/json" -d '{"url":"https://example.com/a?x=1","title":"Example"}'
# 期望：{"success":true,"data":{"url":"https://example.com","title":"Example", ...}}
# 2) 再次 POST 同一 URL：返回同一 id，不新增
# 3) 列表：data 长度 1
curl.exe -s $base -H "Authorization: Bearer test-key"
# 4) 软删除后：列表空、trash 长度 1
# 5) 在回收站状态下再次 POST 同一 URL：同一 id，deleted_at 变 null，trash 空
# 6) 再删除，永久删除 trash/:id 后：trash 空
# 7) 无 token：401；非法 url：400
curl.exe -s -X POST $base -H "Content-Type: application/json" -d '{"url":"not-a-url"}'
# 8) exists
curl.exe -s "$base/exists?url=https%3A%2F%2Fexample.com%2Fb" -H "Authorization: Bearer test-key"
# 期望：{"success":true,"data":{"exists":true,"inTrash":false}}
```

- [ ] **Step 5: 清理并提交**

```bash
rm -rf server/.tmp-sites-test
git add server/src/routes/sites.ts server/src/types/index.ts server/src/utils/url.ts server/src/utils/database.ts server/src/index.ts
git commit -m "feat(server): 新增站点收藏与回收站 API"
```

---

### Task 2: 文档与版本

**Files:**
- Modify: `AGENTS.md`（API 端点表，`/api/stats` 行后追加一行）
- Modify: `server/package.json`（`version` 0.9.0 → 0.10.0）
- Modify: `CHANGELOG.md`（`## [Unreleased]` 下新增 `### Server` → `#### Added`）

**Interfaces:**
- Consumes: Task 1 的端点路径与行为。
- Produces: 文档与版本号，无代码接口。

- [ ] **Step 1: AGENTS.md API 表追加**

在 `/api/stats` 行后加：

```
| GET    | /api/sites                 | 站点列表（不含回收站）                 |
| POST   | /api/sites                 | 新增站点（origin 去重，回收站中则恢复） |
| DELETE | /api/sites/:id             | 删除站点（软删除进回收站）             |
| GET    | /api/sites/trash           | 回收站站点                             |
| POST   | /api/sites/:id/restore     | 还原站点                               |
| DELETE | /api/sites/trash/:id       | 永久删除站点                           |
| GET    | /api/sites/exists          | 检查站点是否存在（含 inTrash）         |
```

- [ ] **Step 2: 版本与 CHANGELOG**

`server/package.json` 改 `"version": "0.10.0"`；CHANGELOG 的 `[Unreleased]` 下加：

```md
### Server

#### Added

- 站点收藏：新增 `sites` 表与 `/api/sites` 路由组（列表、新增、软删除、回收站、还原、永久删除、存在性检查）。
- 站点重复收藏：活跃站点幂等返回；回收站中的站点自动恢复。
```

- [ ] **Step 3: 校验并提交**

```bash
cd server && pnpm typecheck
cd .. && git add AGENTS.md CHANGELOG.md server/package.json
git commit -m "docs(server): 补充站点 API 文档并升级版本"
```
