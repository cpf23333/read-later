/**
 * 鉴权中间件
 */

import { createMiddleware } from 'hono/factory';

// API Key 存储
let API_KEY = '';

export function setApiKey(key: string): void {
  API_KEY = key;
}

export function getApiKey(): string {
  return API_KEY;
}

/**
 * 检查 API Key 是否配置
 */
export function checkApiKeyConfigured(): boolean {
  return !!API_KEY;
}

/**
 * API Key 鉴权中间件
 */
export const authMiddleware = createMiddleware(async (c, next) => {
  const authHeader = c.req.header('authorization');

  if (!authHeader) {
    return c.json({ success: false, error: 'Missing Authorization header' }, 401);
  }

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') {
    return c.json(
      {
        success: false,
        error: 'Invalid Authorization format. Use: Bearer <token>',
      },
      401
    );
  }

  const token = parts[1];
  if (token !== API_KEY) {
    return c.json({ success: false, error: 'Invalid API Key' }, 401);
  }

  await next();
  return;
});

/**
 * 可选鉴权中间件（健康检查等公开接口用）
 */
export const optionalAuthMiddleware = createMiddleware(async (c, next) => {
  // 健康检查不需要鉴权，直接通过
  if (c.req.path === '/api/health') {
    await next();
    return;
  }

  // 其他路径需要鉴权
  return authMiddleware(c, next);
});
