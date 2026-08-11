/**
 * 全局错误处理中间件
 */

import { createMiddleware } from 'hono/factory';
import { logger } from '../utils/logger.ts';

export const errorHandler = createMiddleware(async (c, next) => {
  try {
    await next();
    return;
  } catch (error) {
    const requestInfo = {
      method: c.req.method,
      path: c.req.path,
      query: c.req.query(),
    };

    if (error instanceof Error) {
      logger.error('Unhandled request error', {
        ...requestInfo,
        error: error.message,
        stack: process.env.NODE_ENV === 'production' ? undefined : error.stack,
      });
    } else {
      logger.error('Unhandled unknown error', {
        ...requestInfo,
        error: String(error),
      });
    }

    return c.json(
      {
        success: false,
        error: 'Internal server error',
      },
      500
    );
  }
});
