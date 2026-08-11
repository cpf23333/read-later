/**
 * 限流中间件
 */

import { createMiddleware } from 'hono/factory';

// 简单的内存限流存储
interface RateLimitEntry {
  count: number;
  resetTime: number;
}

const store: Map<string, RateLimitEntry> = new Map();

// 清理过期记录
function cleanupStore(): void {
  const now = Date.now();
  for (const [key, entry] of store.entries()) {
    if (entry.resetTime < now) {
      store.delete(key);
    }
  }
}

// 每 5 分钟清理一次
setInterval(cleanupStore, 5 * 60 * 1000);

interface RateLimitOptions {
  windowMs: number;
  max: number;
  message?: string;
  keyPrefix?: string;
}

function readEnvInt(name: string, defaultValue: number): number {
  const value = process.env[name];
  if (!value) return defaultValue;
  const parsed = parseInt(value, 10);
  return Number.isNaN(parsed) ? defaultValue : parsed;
}

/**
 * 创建限流中间件
 */
export function createRateLimit(options: RateLimitOptions) {
  const { windowMs, max, message = 'Too many requests, please try again later', keyPrefix = '' } = options;

  return createMiddleware(async (c, next) => {
    // 获取客户端标识（优先使用真实 IP）
    const clientId =
      c.req.header('x-forwarded-for') ||
      c.req.header('x-real-ip') ||
      c.req.header('cf-connecting-ip') ||
      'unknown';

    const key = [keyPrefix, c.req.method, c.req.path, clientId].filter(Boolean).join(':');
    const now = Date.now();

    // 检查或初始化记录
    let entry = store.get(key);
    if (!entry || entry.resetTime < now) {
      entry = {
        count: 1,
        resetTime: now + windowMs,
      };
      store.set(key, entry);
    } else {
      entry.count++;
    }

    const remaining = Math.max(0, max - entry.count);
    const resetAt = Math.ceil(entry.resetTime / 1000);

    // 设置响应头
    c.header('X-RateLimit-Limit', max.toString());
    c.header('X-RateLimit-Remaining', remaining.toString());
    c.header('X-RateLimit-Reset', resetAt.toString());

    // 检查是否超过限制
    if (entry.count > max) {
      c.header('Retry-After', Math.ceil(windowMs / 1000).toString());
      return c.json({ success: false, error: message }, 429);
    }

    await next();
    return;
  });
}

// 从环境变量读取限流配置
const generalWindowMs = readEnvInt('RATE_LIMIT_GENERAL_WINDOW_MS', 15 * 60 * 1000);
const generalMax = readEnvInt('RATE_LIMIT_GENERAL_MAX', 100);
const apiWindowMs = readEnvInt('RATE_LIMIT_API_WINDOW_MS', 1 * 60 * 1000);
const apiMax = readEnvInt('RATE_LIMIT_API_MAX', 30);
const exportWindowMs = readEnvInt('RATE_LIMIT_EXPORT_WINDOW_MS', 10 * 60 * 1000);
const exportMax = readEnvInt('RATE_LIMIT_EXPORT_MAX', 5);
const importWindowMs = readEnvInt('RATE_LIMIT_IMPORT_WINDOW_MS', 1 * 60 * 1000);
const importMax = readEnvInt('RATE_LIMIT_IMPORT_MAX', 10);

/**
 * 通用限流
 */
export const generalRateLimit = createRateLimit({
  windowMs: generalWindowMs,
  max: generalMax,
  message: 'Too many requests, please try again later',
  keyPrefix: 'general',
});

/**
 * API 限流（用于添加、删除、修改等操作）
 */
export const apiRateLimit = createRateLimit({
  windowMs: apiWindowMs,
  max: apiMax,
  message: 'Too many API requests, please slow down',
  keyPrefix: 'api',
});

/**
 * 导出限流（导出任务较耗时）
 */
export const exportRateLimit = createRateLimit({
  windowMs: exportWindowMs,
  max: exportMax,
  message: 'Too many export requests, please try again later',
  keyPrefix: 'export',
});

/**
 * 导入限流（导入可能批量写入）
 */
export const importRateLimit = createRateLimit({
  windowMs: importWindowMs,
  max: importMax,
  message: 'Too many import requests, please try again later',
  keyPrefix: 'import',
});
