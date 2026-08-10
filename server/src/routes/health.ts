/**
 * 健康检查路由
 */

import { Hono } from 'hono';
import type { ApiResponse } from '../types/index.ts';

const app = new Hono();

/**
 * 健康检查
 * GET /api/health
 */
app.get('/', async (c) => {
  return c.json<ApiResponse<{ message: string }>>({
    success: true,
    data: { message: 'ReadLater Server OK' },
  });
});

export default app;
