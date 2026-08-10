/**
 * 图片上传路由（兼容）
 */

import { Hono } from 'hono';
import { processImage } from '../utils/image.ts';
import type { UploadBody, ApiResponse } from '../types/index.ts';

const app = new Hono();

/**
 * 上传图片
 * POST /api/upload
 */
app.post('/', async (c) => {
  const body = await c.req.json<UploadBody>();
  const { image } = body;

  if (!image) {
    return c.json<ApiResponse>({ success: false, error: 'No image' }, 400);
  }

  const result = await processImage(image, 'upload');
  if (!result) {
    return c.json<ApiResponse>(
      {
        success: false,
        error: 'Invalid image data',
      },
      400
    );
  }

  return c.json<ApiResponse<{ url: string }>>({
    success: true,
    data: { url: result },
  });
});

export default app;
