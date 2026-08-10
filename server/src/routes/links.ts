/**
 * 链接相关路由
 */

import { Hono } from 'hono';
import {
  getLinks,
  searchLinks,
  getLinkById,
  findLinkByNormalizedUrl,
  addLink,
  deleteLink,
  addToTrash,
  exportLinks,
  batchInsertLinks,
  batchDeleteLinks,
} from '../utils/database.ts';
import { processImage, moveImageToTrash } from '../utils/image.ts';
import { sanitizeId, sanitizeSearchQuery } from '../utils/security.ts';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import type {
  Link,
  CreateLinkBody,
  BatchCreateBody,
  ImportBody,
  ApiResponse,
  PaginatedResponse,
} from '../types/index.ts';

const app = new Hono();

/**
 * 获取所有链接
 * GET /api/links
 */
app.get('/', async (c) => {
  const query = c.req.query();

  const page = parseInt(query.page || '1', 10);
  const pageSize = parseInt(query.pageSize || '50', 10);
  const sortBy = query.sortBy || 'created_at';
  const sortOrder = (query.sortOrder || 'desc') as 'asc' | 'desc';
  const search = query.search;
  const domain = query.domain;

  const { links, total } = getLinks(page, pageSize, sortBy, sortOrder, search, domain);

  // 日志输出第一个链接的图片字段
  if (links.length > 0) {
    console.log('[getLinks] First link images:', {
      url: links[0]!.url,
      nearby_image: links[0]!.nearby_image,
      screenshot: links[0]!.screenshot,
    });
  }

  return c.json<ApiResponse<PaginatedResponse<Link>>>({
    success: true,
    data: { data: links, total },
  });
});

/**
 * 搜索链接
 * GET /api/search
 */
app.get('/search', async (c) => {
  const { q } = c.req.query();

  if (!q || typeof q !== 'string') {
    return c.json<ApiResponse<Link[]>>({ success: true, data: [] });
  }

  const sanitizedQuery = sanitizeSearchQuery(q);
  if (!sanitizedQuery) {
    return c.json<ApiResponse<Link[]>>({ success: true, data: [] });
  }

  const links = searchLinks(sanitizedQuery);

  return c.json<ApiResponse<Link[]>>({ success: true, data: links });
});

/**
 * 添加链接
 * POST /api/links
 */
app.post('/', apiRateLimit, async (c) => {
  const body = await c.req.json<CreateLinkBody>();

  const { id, url, title, nearby_image, screenshot, source_page, created_at, custom_data } = body;

  console.log('[Server] Received link:', {
    url,
    nearby_image: nearby_image ? `${nearby_image.substring(0, 50)}...` : null,
    screenshot: screenshot ? `${screenshot.substring(0, 50)}...` : null,
  });

  // 处理图片
  const nearbyImagePath = await processImage(nearby_image, 'nearby');
  const screenshotPath = await processImage(screenshot, 'screenshot');

  console.log('[Server] Processed images:', {
    nearbyImagePath,
    screenshotPath,
  });

  const now = Date.now();

  addLink({
    id: id || `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
    url,
    title: title || '',
    nearby_image: nearbyImagePath,
    screenshot: screenshotPath,
    source_page: source_page || '',
    created_at: created_at || now,
    custom_data: JSON.stringify(custom_data || {}),
  });

  return c.json<ApiResponse>({ success: true });
});

/**
 * 批量添加链接
 * POST /api/links/batch
 */
app.post('/batch', apiRateLimit, async (c) => {
  const body = await c.req.json<BatchCreateBody>();
  const { links } = body;

  // 参数校验
  if (!Array.isArray(links)) {
    return c.json<ApiResponse>({ success: false, error: 'links must be an array' }, 400);
  }
  if (links.length === 0) {
    return c.json<ApiResponse>({ success: false, error: 'links array is empty' }, 400);
  }
  if (links.length > 500) {
    return c.json<ApiResponse>({ success: false, error: 'Batch size exceeds maximum of 500' }, 400);
  }

  // 先异步处理所有图片（processImage 内部已兜底，不会抛错）
  const processed = [];
  for (let i = 0; i < links.length; i++) {
    const item = links[i];
    if (!item || !item.url) {
      continue;
    }
    try {
      const nearbyImagePath = await processImage(item.nearby_image || item.nearbyImage, 'nearby');
      const screenshotPath = await processImage(item.screenshot, 'screenshot');

      processed.push({
        id: item.id || `${Date.now()}_${Math.random().toString(36).substring(2, 9)}_${i}`,
        url: item.url,
        title: item.title || '',
        nearby_image: nearbyImagePath,
        screenshot: screenshotPath,
        source_page: item.source_page || item.sourcePage || '',
        created_at: item.created_at || item.createdAt || Date.now(),
        custom_data: JSON.stringify(item.custom_data || item.customData || {}),
      });
    } catch (e) {
      console.error('[batch] Image processing failed for:', item.url, e);
    }
  }

  // 使用事务批量插入，单条失败不影响其他
  const { succeeded, failed } = batchInsertLinks(processed);

  return c.json<ApiResponse<{ count: number; total: number; failed: number }>>({
    success: true,
    data: { count: succeeded, total: links.length, failed },
  });
});

/**
 * 检查链接是否已存在（基于标准化 URL）
 * GET /api/links/exists?url=...
 */
app.get('/exists', async (c) => {
  const { url } = c.req.query();

  if (!url || typeof url !== 'string') {
    return c.json<ApiResponse>({ success: false, error: 'url is required' }, 400);
  }

  const existing = findLinkByNormalizedUrl(url);

  return c.json<ApiResponse<{ exists: boolean; link?: Link }>>({
    success: true,
    data: { exists: !!existing, link: existing },
  });
});

/**
 * 批量检查链接是否已存在
 * POST /api/links/check-batch
 */
app.post('/check-batch', apiRateLimit, async (c) => {
  const body = await c.req.json<{ urls?: string[] }>();
  const urls = body.urls;

  if (!Array.isArray(urls)) {
    return c.json<ApiResponse>({ success: false, error: 'urls must be an array' }, 400);
  }

  const existingNormalizedUrls = new Set<string>();

  for (const url of urls) {
    if (typeof url !== 'string') continue;
    const existing = findLinkByNormalizedUrl(url);
    if (existing) {
      existingNormalizedUrls.add(existing.normalized_url || existing.url);
    }
  }

  return c.json<ApiResponse<{ existingUrls: string[] }>>({
    success: true,
    data: { existingUrls: Array.from(existingNormalizedUrls) },
  });
});

/**
 * 批量删除链接（移入回收站）
 * POST /api/links/batch-delete
 */
app.post('/batch-delete', apiRateLimit, async (c) => {
  const body = await c.req.json<{ ids?: string[] }>();
  const ids = body.ids;

  if (!Array.isArray(ids) || ids.length === 0) {
    return c.json<ApiResponse>({ success: false, error: 'ids must be a non-empty array' }, 400);
  }

  const { succeeded, failed } = batchDeleteLinks(ids);

  return c.json<ApiResponse<{ succeeded: number; failed: number }>>({
    success: true,
    data: { succeeded, failed },
  });
});

/**
 * 删除链接（移入回收站）
 * DELETE /api/links/:id
 */
app.delete('/:id', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));

  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  const link = getLinkById(id);
  if (!link) {
    return c.json<ApiResponse>({ success: false, error: 'Link not found' }, 404);
  }

  // 移入回收站
  const trashId = `delete_${link.id}_${Date.now()}`;

  addToTrash(
    {
      link_id: link.id,
      url: link.url,
      title: link.title,
      nearby_image: link.nearby_image,
      screenshot: link.screenshot,
      source_page: link.source_page,
      created_at: link.created_at,
      deleted_at: Date.now(),
      custom_data: link.custom_data,
    },
    trashId
  );

  // 从主表删除
  deleteLink(id);

  // 移动图片到回收站目录
  for (const imgPath of [link.nearby_image, link.screenshot]) {
    if (imgPath) {
      moveImageToTrash(imgPath);
    }
  }

  return c.json<ApiResponse>({ success: true });
});

/**
 * 导出所有链接
 * GET /api/export
 */
app.get('/export', async (c) => {
  const links = exportLinks();
  return c.json<ApiResponse<Link[]>>({ success: true, data: links });
});

/**
 * 导入链接
 * POST /api/import
 */
app.post('/import', apiRateLimit, async (c) => {
  const body = await c.req.json<ImportBody>();
  const { links, mode = 'merge' } = body;

  if (!Array.isArray(links)) {
    return c.json<ApiResponse>({ success: false, error: 'links must be an array' }, 400);
  }

  if (mode === 'replace') {
    // 清空现有链接
    const allLinks = exportLinks();
    for (const link of allLinks) {
      deleteLink(link.id);
    }
  }

  let imported = 0;
  for (const item of links) {
    try {
      // 处理图片
      const nearbyImagePath = await processImage(item.nearby_image || item.nearbyImage, 'nearby');
      const screenshotPath = await processImage(item.screenshot, 'screenshot');

      addLink({
        id: item.id || `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
        url: item.url,
        title: item.title || '',
        nearby_image: nearbyImagePath,
        screenshot: screenshotPath,
        source_page: item.source_page || item.sourcePage || '',
        created_at: item.created_at || item.createdAt || Date.now(),
        custom_data:
          typeof item.custom_data === 'string'
            ? item.custom_data
            : JSON.stringify(item.custom_data || item.customData || {}),
      });
      imported++;
    } catch (e) {
      // 忽略错误，继续处理下一个
    }
  }

  return c.json<ApiResponse<{ imported: number; total: number }>>({
    success: true,
    data: { imported, total: links.length },
  });
});

export default app;
