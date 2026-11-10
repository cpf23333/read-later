/**
 * 链接导入路由
 *
 * POST /api/import
 *
 * 针对“一次导入大量 URL”优化：
 * - 纯 URL（标签页导入）跳过图片处理；
 * - 单事务批量插入，避免逐条 INSERT 的事务/fsync 开销；
 * - replace 模式单事务清空；
 * - 单次上限 5000 条。
 */

import { Hono } from 'hono';
import { processImage } from '../utils/image.ts';
import {
  batchInsertLinks,
  clearLinks,
} from '../utils/database.ts';
import { importRateLimit } from '../middleware/ratelimit.ts';
import type { ImportBody, ApiResponse } from '../types/index.ts';

const app = new Hono();

app.post('/', importRateLimit, async (c) => {
  const body = await c.req.json<ImportBody>();
  const { links, mode = 'merge' } = body;

  if (!Array.isArray(links)) {
    return c.json<ApiResponse>(
      { success: false, error: 'links must be an array' },
      400
    );
  }
  if (links.length > 5000) {
    return c.json<ApiResponse>(
      { success: false, error: 'Import size exceeds maximum of 5000' },
      400
    );
  }

  if (mode === 'replace') {
    clearLinks();
  }

  const processed: Array<{
    id: string;
    url: string;
    title: string;
    nearby_image: string | null;
    screenshot: string | null;
    source_page: string;
    created_at: number;
    custom_data: string;
  }> = [];

  for (let i = 0; i < links.length; i++) {
    const item = links[i];
    if (!item || !item.url) continue;
    try {
      // 纯 URL 导入不触发图片处理，避免无意义的 I/O。
      const nearbySource = item.nearby_image || item.nearbyImage;
      const screenshotSource = item.screenshot;
      const nearbyImagePath = nearbySource
        ? await processImage(nearbySource, 'nearby')
        : null;
      const screenshotPath = screenshotSource
        ? await processImage(screenshotSource, 'screenshot')
        : null;

      processed.push({
        id:
          item.id ||
          `${Date.now()}_${Math.random().toString(36).substring(2, 9)}_${i}`,
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
    } catch (e) {
      console.error('[import] Failed to prepare item:', item.url, e);
    }
  }

  // 单事务批量写入，单条失败不影响其他。
  const { succeeded, failed } = batchInsertLinks(processed);

  return c.json<
    ApiResponse<{ imported: number; total: number; failed: number }>
  >({
    success: true,
    data: { imported: succeeded, total: links.length, failed },
  });
});

export default app;
