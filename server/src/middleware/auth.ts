/**
 * 鉴权中间件
 */

import { createMiddleware } from 'hono/factory';

// API Key 存储（支持多个 Key，便于轮换）
const API_KEYS = new Set<string>();

/**
 * 设置单个 API Key（兼容旧接口）
 * 支持逗号分隔的多个 Key
 */
export function setApiKey(key: string): void {
  setApiKeys(key.split(',').map((k) => k.trim()).filter(Boolean));
}

/**
 * 设置多个 API Key
 */
export function setApiKeys(keys: string[]): void {
  API_KEYS.clear();
  for (const key of keys) {
    if (key.trim()) {
      API_KEYS.add(key.trim());
    }
  }
}

/**
 * 获取已配置的 API Key 数量
 */
export function getApiKeyCount(): number {
  return API_KEYS.size;
}

/**
 * 检查 API Key 是否配置
 */
export function checkApiKeyConfigured(): boolean {
  return API_KEYS.size > 0;
}

/**
 * 验证 API Key 是否有效
 */
export function validateApiKey(token: string): boolean {
  return API_KEYS.has(token);
}

/**
 * 获取所有 API Key 的掩码列表（用于管理接口）
 */
export function getMaskedApiKeys(): string[] {
  return Array.from(API_KEYS).map((key) => {
    if (key.length <= 8) return '*'.repeat(key.length);
    return key.slice(0, 4) + '...' + key.slice(-4);
  });
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
  const scheme = parts[0];
  const token = parts[1];
  if (parts.length !== 2 || scheme !== 'Bearer' || !token) {
    return c.json(
      {
        success: false,
        error: 'Invalid Authorization format. Use: Bearer <token>',
      },
      401
    );
  }

  if (!validateApiKey(token)) {
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
