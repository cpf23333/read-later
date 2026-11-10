/**
 * 站点收藏路由
 *
 * GET    /api/sites                 站点列表（不含回收站）
 * POST   /api/sites                 新增站点（origin 去重，回收站中则恢复）
 * DELETE /api/sites/:id             软删除（进回收站）
 * GET    /api/sites/trash           回收站站点
 * POST   /api/sites/:id/restore     还原站点
 * DELETE /api/sites/trash/:id       永久删除
 * GET    /api/sites/exists          站点是否存在（含 inTrash）
 */

import { Hono } from 'hono';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import { sanitizeId } from '../utils/security.ts';
import { normalizeOrigin } from '../utils/url.ts';
import {
  addSite,
  getSiteById,
  getSiteByOrigin,
  getSites,
  getSiteTrash,
  reviveSite,
  softDeleteSite,
  restoreSite,
  deleteSitePermanently,
  updateSite,
} from '../utils/database.ts';
import type { Site, SiteInput, SiteUpdateInput, ApiResponse, SiteExistsResponse } from '../types/index.ts';

const app = new Hono();

/**
 * 回收站站点列表
 * 必须注册在 /:id 之前
 */
app.get('/trash', async (c) => {
  return c.json<ApiResponse<Site[]>>({ success: true, data: getSiteTrash() });
});

/**
 * 永久删除站点（仅回收站内记录）
 */
app.delete('/trash/:id', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));
  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  deleteSitePermanently(id);
  return c.json<ApiResponse>({ success: true });
});

/**
 * 检查站点是否存在（按 origin）
 */
app.get('/exists', async (c) => {
  const { url } = c.req.query();

  if (!url || typeof url !== 'string') {
    return c.json<ApiResponse>({ success: false, error: 'url is required' }, 400);
  }

  const origin = normalizeOrigin(url);
  if (!origin) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid URL' }, 400);
  }

  const site = getSiteByOrigin(origin);
  return c.json<ApiResponse<SiteExistsResponse>>({
    success: true,
    data: {
      exists: !!site && site.deleted_at === null,
      inTrash: !!site && site.deleted_at !== null,
    },
  });
});

/**
 * 站点列表
 */
app.get('/', async (c) => {
  return c.json<ApiResponse<Site[]>>({ success: true, data: getSites() });
});

/**
 * 新增站点
 */
app.post('/', apiRateLimit, async (c) => {
  const body = await c.req.json<SiteInput>().catch(() => null);
  if (!body || typeof body.url !== 'string') {
    return c.json<ApiResponse>({ success: false, error: 'url is required' }, 400);
  }

  const origin = normalizeOrigin(body.url);
  if (!origin) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid URL' }, 400);
  }

  const title = (typeof body.title === 'string' && body.title.trim()) || origin;
  const iconUrl =
    typeof body.icon_url === 'string' && body.icon_url.trim() ? body.icon_url.trim() : null;
  const userAgentMode = normalizeUaMode(body.user_agent_mode) || 'default';
  const userAgent =
    typeof body.user_agent === 'string' && body.user_agent.trim()
      ? body.user_agent.trim()
      : null;
  if (userAgentMode === 'custom' && !userAgent) {
    return c.json<ApiResponse>({ success: false, error: 'user_agent is required for custom mode' }, 400);
  }

  const existing = getSiteByOrigin(origin);
  if (existing) {
    if (existing.deleted_at === null) {
      return c.json<ApiResponse<Site>>({ success: true, data: existing });
    }
    return c.json<ApiResponse<Site>>({
      success: true,
      data: reviveSite(existing, title, iconUrl),
    });
  }

  const site = addSite({
    url: origin,
    title,
    icon_url: iconUrl,
    user_agent_mode: userAgentMode,
    user_agent: userAgent,
  });
  return c.json<ApiResponse<Site>>({ success: true, data: site });
});

const UA_MODES = new Set(['default', 'desktop', 'custom']);

function normalizeUaMode(value: unknown): 'default' | 'desktop' | 'custom' | undefined {
  return typeof value === 'string' && UA_MODES.has(value)
    ? (value as 'default' | 'desktop' | 'custom')
    : undefined;
}

/**
 * 更新站点（标题/图标/User-Agent 配置）
 * PATCH /api/sites/:id
 */
app.patch('/:id', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));
  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  const site = getSiteById(id);
  if (!site || site.deleted_at !== null) {
    return c.json<ApiResponse>({ success: false, error: 'Not found' }, 404);
  }

  const body = await c.req.json<SiteUpdateInput>().catch(() => null);
  if (!body) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid body' }, 400);
  }

  const fields: Parameters<typeof updateSite>[1] = {};
  if (typeof body.title === 'string') fields.title = body.title.trim();
  if (body.icon_url === null || typeof body.icon_url === 'string') {
    fields.icon_url = body.icon_url === null ? null : body.icon_url.trim() || null;
  }
  if (body.user_agent_mode !== undefined) {
    const mode = normalizeUaMode(body.user_agent_mode);
    if (!mode) {
      return c.json<ApiResponse>({ success: false, error: 'Invalid user_agent_mode' }, 400);
    }
    fields.user_agent_mode = mode;
  }
  if (body.user_agent === null || typeof body.user_agent === 'string') {
    fields.user_agent = body.user_agent === null ? null : body.user_agent.trim() || null;
  }

  if (fields.user_agent_mode === 'custom' && !fields.user_agent && !site.user_agent) {
    return c.json<ApiResponse>({ success: false, error: 'user_agent is required for custom mode' }, 400);
  }

  const updated = updateSite(id, fields);
  return c.json<ApiResponse<Site>>({ success: true, data: updated });
});

/**
 * 软删除站点（进回收站）
 */
app.delete('/:id', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));
  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  const site = getSiteById(id);
  if (!site) {
    return c.json<ApiResponse>({ success: false, error: 'Not found' }, 404);
  }

  if (site.deleted_at === null) {
    softDeleteSite(id);
  }

  return c.json<ApiResponse>({ success: true });
});

/**
 * 还原站点
 */
app.post('/:id/restore', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));
  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  const site = getSiteById(id);
  if (!site || site.deleted_at === null) {
    return c.json<ApiResponse>({ success: false, error: 'Not found in trash' }, 404);
  }

  restoreSite(id);
  return c.json<ApiResponse>({ success: true });
});

export default app;
