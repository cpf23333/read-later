/**
 * 链接相关路由
 */

import { Hono } from 'hono';
import { getLinks, searchLinks, getLinkById, addLink, deleteLink, addToTrash, exportLinks } from '../utils/database.ts';
import { processImage } from '../utils/image.ts';
import { sanitizeId, sanitizeSearchQuery } from '../utils/security.ts';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import type { Link, CreateLinkBody, BatchCreateBody, ImportBody, ApiResponse, PaginatedResponse } from '../types/index.ts';

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
      url: links[0].url,
      nearby_image: links[0].nearby_image,
      screenshot: links[0].screenshot,
    });
  }

  return c.json<ApiResponse<PaginatedResponse<Link>>>({
    success: true,
    data: { data: links, total }
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
  
  const {
    id,
    url,
    title,
    nearby_image,
    screenshot,
    source_page,
    created_at,
    custom_data,
  } = body;

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

  for (const item of links) {
    // 处理图片
    const nearbyImagePath = await processImage(
      item.nearby_image || item.nearbyImage,
      'nearby',
    );
    const screenshotPath = await processImage(item.screenshot, 'screenshot');

    addLink({
      id: item.id,
      url: item.url,
      title: item.title || '',
      nearby_image: nearbyImagePath,
      screenshot: screenshotPath,
      source_page: item.source_page || item.sourcePage || '',
      created_at: item.created_at || item.createdAt || Date.now(),
      custom_data: JSON.stringify(item.custom_data || item.customData || {}),
    });
  }

  return c.json<ApiResponse<{ count: number }>>({ 
    success: true, 
    data: { count: links.length } 
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
  
  addToTrash({
    link_id: link.id,
    url: link.url,
    title: link.title,
    nearby_image: link.nearby_image,
    screenshot: link.screenshot,
    source_page: link.source_page,
    created_at: link.created_at,
    deleted_at: Date.now(),
    custom_data: link.custom_data,
  }, trashId);

  // 从主表删除
  deleteLink(id);

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
      const nearbyImagePath = await processImage(
        item.nearby_image || item.nearbyImage,
        'nearby',
      );
      const screenshotPath = await processImage(
        item.screenshot,
        'screenshot',
      );

      addLink({
        id: item.id || `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
        url: item.url,
        title: item.title || '',
        nearby_image: nearbyImagePath,
        screenshot: screenshotPath,
        source_page: item.source_page || item.sourcePage || '',
        created_at: item.created_at || item.createdAt || Date.now(),
        custom_data: typeof item.custom_data === 'string' 
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
    data: { imported, total: links.length }
  });
});

export default app;
