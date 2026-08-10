/**
 * 回收站相关路由
 */

import { Hono } from 'hono';
import { getTrashItems, getTrashItemById, deleteFromTrash, addLink } from '../utils/database.ts';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import { sanitizeId } from '../utils/security.ts';
import type { TrashItem, ApiResponse } from '../types/index.ts';
import fs from 'fs';
import path from 'path';
import { getImagesDir } from '../utils/image.ts';

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

  // 还原图片（保持原文件名）
  const IMAGES_DIR = getImagesDir();
  const DELETED_IMAGES_DIR = path.join(IMAGES_DIR, 'deleted');

  [item.nearby_image, item.screenshot].forEach((imgPath) => {
    if (imgPath && imgPath.startsWith('/images/')) {
      const filename = path.basename(imgPath);
      const oldPath = path.join(DELETED_IMAGES_DIR, filename);
      const newPath = path.join(IMAGES_DIR, filename);
      if (fs.existsSync(oldPath)) {
        fs.renameSync(oldPath, newPath);
      }
    }
  });

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
    // 删除图片（使用原文件名）
    const IMAGES_DIR = getImagesDir();
    const DELETED_IMAGES_DIR = path.join(IMAGES_DIR, 'deleted');

    [item.nearby_image, item.screenshot].forEach((imgPath) => {
      if (imgPath && imgPath.startsWith('/images/')) {
        const filename = path.basename(imgPath);
        const filePath = path.join(DELETED_IMAGES_DIR, filename);
        if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
      }
    });
  }

  deleteFromTrash(id);

  return c.json<ApiResponse>({ success: true });
});

export default app;
