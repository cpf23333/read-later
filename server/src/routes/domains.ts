/**
 * 域名统计路由
 */

import { Hono } from 'hono';
import { getDomainStats } from '../utils/database.ts';
import type { DomainStat, ApiResponse } from '../types/index.ts';

const app = new Hono();

/**
 * 获取域名统计
 * GET /api/domains
 */
app.get('/', async (c) => {
  const result = getDomainStats();
  return c.json<ApiResponse<DomainStat[]>>({ success: true, data: result });
});

export default app;
