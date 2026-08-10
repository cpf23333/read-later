/**
 * 回收站相关路由
 */

import { Hono } from 'hono';
import {
  getTrashItems,
  getTrashItemById,
  deleteFromTrash,
  addLink,
  batchRestoreFromTrash,
  batchPermanentlyDelete,
} from '../utils/database.ts';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import { sanitizeId } from '../utils/security.ts';
import type { TrashItem, ApiResponse } from '../types/index.ts';
import { restoreImageFromTrash, deleteImageFile } from '../utils/image.ts';

const app = new Hono();

/**
 * 获取回收站所有项目
 * GET /api/trash
 */
app.get('/', async (c) => {
  const items = getTrashItems();

  // 转换图片路径为 deleted 目录
  const itemsWithFixedPaths = items.map((item) => ({
    ...item,
    nearby_image:
      item.nearby_image && item.nearby_image.startsWith('/images/')
        ? item.nearby_image.replace('/images/', '/images/deleted/')
        : item.nearby_image,
    screenshot:
      item.screenshot && item.screenshot.startsWith('/images/')
        ? item.screenshot.replace('/images/', '/images/deleted/')
        : item.screenshot,
  }));

  return c.json<ApiResponse<TrashItem[]>>({
    success: true,
    data: itemsWithFixedPaths,
  });
});

/**
 * 还原链接
 * POST /api/trash/:id/restore
 */
app.post('/:id/restore', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));

  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  const item = getTrashItemById(id);
  if (!item) {
    return c.json<ApiResponse>({ success: false, error: 'Not found' }, 404);
  }

  const newId = `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

  addLink({
    id: newId,
    url: item.url,
    title: item.title,
    nearby_image: item.nearby_image,
    screenshot: item.screenshot,
    source_page: item.source_page,
    created_at: Date.now(),
    custom_data: item.custom_data,
  });

  deleteFromTrash(id);

  // 还原图片（包括缩略图）
  for (const imgPath of [item.nearby_image, item.screenshot]) {
    if (imgPath) {
      restoreImageFromTrash(imgPath);
    }
  }

  return c.json<ApiResponse<{ newId: string }>>({
    success: true,
    data: { newId },
  });
});

/**
 * 永久删除
 * DELETE /api/trash/:id
 */
app.delete('/:id', apiRateLimit, async (c) => {
  const id = sanitizeId(c.req.param('id'));

  if (!id) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid ID' }, 400);
  }

  const item = getTrashItemById(id);
  if (item) {
    // 删除图片（包括缩略图）
    for (const imgPath of [item.nearby_image, item.screenshot]) {
      if (imgPath) {
        deleteImageFile(imgPath);
      }
    }
  }

  deleteFromTrash(id);

  return c.json<ApiResponse>({ success: true });
});

/**
 * 批量还原回收站项目
 * POST /api/trash/batch-restore
 */
app.post('/batch-restore', apiRateLimit, async (c) => {
  const body = await c.req.json<{ ids?: string[] }>();
  const ids = body.ids;

  if (!Array.isArray(ids) || ids.length === 0) {
    return c.json<ApiResponse>({ success: false, error: 'ids must be a non-empty array' }, 400);
  }

  const { succeeded, failed, newIds } = batchRestoreFromTrash(ids);

  return c.json<ApiResponse<{ succeeded: number; failed: number; newIds: string[] }>>({
    success: true,
    data: { succeeded, failed, newIds },
  });
});

/**
 * 批量永久删除回收站项目
 * POST /api/trash/batch-delete
 */
app.post('/batch-delete', apiRateLimit, async (c) => {
  const body = await c.req.json<{ ids?: string[] }>();
  const ids = body.ids;

  if (!Array.isArray(ids) || ids.length === 0) {
    return c.json<ApiResponse>({ success: false, error: 'ids must be a non-empty array' }, 400);
  }

  const { succeeded, failed } = batchPermanentlyDelete(ids);

  return c.json<ApiResponse<{ succeeded: number; failed: number }>>({
    success: true,
    data: { succeeded, failed },
  });
});

export default app;
