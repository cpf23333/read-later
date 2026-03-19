/**
 * 统计信息路由
 */

import { Hono } from 'hono';
import { getStats } from '../utils/database.ts';
import type { Stats, ApiResponse } from '../types/index.ts';

const app = new Hono();

/**
 * 获取统计信息
 * GET /api/stats
 */
app.get('/', async (c) => {
  const stats = getStats();
  return c.json<ApiResponse<Stats>>({ success: true, data: stats });
});

export default app;
