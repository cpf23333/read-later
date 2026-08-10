/**
 * 限流中间件
 */

import { createMiddleware } from 'hono/factory';

// 简单的内存限流存储
interface RateLimitStore {
  [key: string]: {
    count: number;
    resetTime: number;
  };
}

const store: RateLimitStore = {};

// 清理过期记录
function cleanupStore(): void {
  const now = Date.now();
  for (const key in store) {
    const entry = store[key];
    if (entry && entry.resetTime < now) {
      delete store[key];
    }
  }
}

// 每 5 分钟清理一次
setInterval(cleanupStore, 5 * 60 * 1000);

interface RateLimitOptions {
  windowMs: number;
  max: number;
  message?: string;
}

/**
 * 创建限流中间件
 */
export function createRateLimit(options: RateLimitOptions) {
  const { windowMs, max, message = 'Too many requests, please try again later' } = options;

  return createMiddleware(async (c, next) => {
    // 获取客户端标识（优先使用 IP）
    const clientId = c.req.header('x-forwarded-for') || c.req.header('x-real-ip') || 'unknown';

    const key = `${c.req.path}:${clientId}`;
    const now = Date.now();

    // 检查或初始化记录
    if (!store[key] || store[key].resetTime < now) {
      store[key] = {
        count: 1,
        resetTime: now + windowMs,
      };
    } else {
      store[key].count++;
    }

    // 检查是否超过限制
    if (store[key].count > max) {
      return c.json({ success: false, error: message }, 429);
    }

    await next();
    return;
  });
}

/**
 * 通用限流：15 分钟 100 请求
 */
export const generalRateLimit = createRateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many requests, please try again later',
});

/**
 * API 限流：1 分钟 30 请求（用于添加、删除等操作）
 */
export const apiRateLimit = createRateLimit({
  windowMs: 1 * 60 * 1000,
  max: 30,
  message: 'Too many API requests, please slow down',
});
