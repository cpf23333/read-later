/**
 * 健康检查路由
 */

import { Hono } from 'hono';
import { checkHealth } from '../utils/health.ts';
import type { ApiResponse } from '../types/index.ts';

const app = new Hono();

/**
 * 健康检查
 * GET /api/health
 */
app.get('/', async (c) => {
  const dataDir = process.env.DATA_DIR || './data';
  const health = checkHealth(dataDir);

  const statusCode = health.status === 'unhealthy' ? 503 : 200;

  return c.json<
    ApiResponse<{
      status: string;
      version: string;
      timestamp: string;
      uptime: number;
      database: {
        connected: boolean;
        linkCount: number;
        trashCount: number;
      };
      disk: {
        dataDir: string;
        free: number;
        total: number;
        usagePercent: number;
      };
      memory: {
        used: number;
        total: number;
        usagePercent: number;
      };
    }>
  >(
    {
      success: health.status !== 'unhealthy',
      data: {
        status: health.status,
        version: health.version,
        timestamp: health.timestamp,
        uptime: health.uptime,
        database: {
          connected: health.database.connected,
          linkCount: health.database.linkCount,
          trashCount: health.database.trashCount,
        },
        disk: health.disk,
        memory: health.memory,
      },
      error: health.database.error,
    },
    statusCode
  );
});

export default app;
