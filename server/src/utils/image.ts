/**
 * 图片处理工具
 */

import fs from 'fs';
import path from 'path';
import { ALLOWED_IMAGE_TYPES, isSafeFilePath, isValidImageUrl } from './security.ts';

// 从环境变量获取配置
const MAX_IMAGE_SIZE = (parseInt(process.env.MAX_IMAGE_SIZE_MB || '10', 10)) * 1024 * 1024;

// 图片目录（需要在初始化后设置）
let IMAGES_DIR = '';

export function setImagesDir(dir: string): void {
  IMAGES_DIR = dir;
}

export function getImagesDir(): string {
  return IMAGES_DIR;
}

/**
 * 将 Base64 数据保存为文件
 */
export function saveBase64ToFile(base64Data: string, prefix: string): string | null {
  try {
    console.log('[saveBase64ToFile] Input length:', base64Data.length);
    console.log('[saveBase64ToFile] Prefix:', prefix);

    // 验证数据大小（粗略估计）
    if (base64Data.length > MAX_IMAGE_SIZE * 2) {
      console.error('[saveBase64ToFile] Image too large');
      return null;
    }

    // 提取 MIME 类型并验证
    const mimeMatch = base64Data.match(/^data:(image\/\w+);base64,/);
    if (mimeMatch) {
      const mimeType = mimeMatch[1];
      if (!ALLOWED_IMAGE_TYPES.includes(mimeType as typeof ALLOWED_IMAGE_TYPES[number])) {
        console.error('[saveBase64ToFile] Invalid image type:', mimeType);
        return null;
      }
    }

    const cleanBase64 = base64Data.replace(/^data:image\/\w+;base64,/, '');
    console.log('[saveBase64ToFile] After regex, length:', cleanBase64.length);

    const buffer = Buffer.from(cleanBase64, 'base64');
    console.log('[saveBase64ToFile] Buffer size:', buffer.length);

    // 验证解码后大小
    if (buffer.length > MAX_IMAGE_SIZE) {
      console.error('[saveBase64ToFile] Image too large after decode:', buffer.length);
      return null;
    }

    // 根据 prefix 选择扩展名
    const ext = prefix === 'screenshot' ? 'jpg' : 'png';
    const filename = `${Date.now()}_${prefix}_${Math.random().toString(36).substring(2, 9)}.${ext}`;
    const filepath = path.join(IMAGES_DIR, filename);

    // 验证文件路径安全
    if (!isSafeFilePath(filename, IMAGES_DIR)) {
      console.error('[saveBase64ToFile] Invalid file path');
      return null;
    }

    console.log('[saveBase64ToFile] Saving to:', filepath);
    fs.writeFileSync(filepath, buffer);
    console.log('[saveBase64ToFile] Saved successfully:', filename);

    return filename;
  } catch (error) {
    console.error('[saveBase64ToFile] Failed to save image:', (error as Error).message);
    console.error((error as Error).stack);
    return null;
  }
}

/**
 * 下载网络图片
 */
export async function downloadImage(url: string, prefix: string): Promise<string | null> {
  try {
    // 验证 URL
    if (!isValidImageUrl(url)) {
      console.warn(`[downloadImage] Invalid URL: ${url}`);
      return null;
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.warn(`[downloadImage] Failed: HTTP ${response.status}`);
      return null;
    }

    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.startsWith('image/')) {
      console.warn(`[downloadImage] Not an image: ${contentType}`);
      return null;
    }

    // 验证图片类型
    if (!ALLOWED_IMAGE_TYPES.some(type => contentType.includes(type.replace('image/', '')))) {
      console.warn(`[downloadImage] Unsupported image type: ${contentType}`);
      return null;
    }

    const buffer = Buffer.from(await response.arrayBuffer());

    if (buffer.length > MAX_IMAGE_SIZE) {
      console.warn(`[downloadImage] Too large: ${buffer.length} bytes`);
      return null;
    }

    const ext = prefix === 'screenshot'
      ? 'jpg'
      : contentType.includes('png')
        ? 'png'
        : 'jpg';
    
    const filename = `${Date.now()}_${prefix}_${Math.random().toString(36).substring(2, 9)}.${ext}`;
    const filepath = path.join(IMAGES_DIR, filename);

    if (!isSafeFilePath(filename, IMAGES_DIR)) {
      console.error('[downloadImage] Invalid file path');
      return null;
    }

    fs.writeFileSync(filepath, buffer);
    console.log(`[downloadImage] Saved: ${filename}`);
    return filename;
  } catch (error) {
    console.error(`[downloadImage] Error:`, (error as Error).message);
    return null;
  }
}

/**
 * 处理图片数据（base64 / URL / 路径）
 */
export async function processImage(imageData: string | undefined, prefix: string): Promise<string | null> {
  if (!imageData) return null;

  console.log(`[processImage] ${prefix}:`, imageData.substring(0, 60) + '...');

  // 如果已经是路径，直接返回
  if (imageData.startsWith('/images/')) {
    return imageData;
  }

  // 如果是 Base64，保存为文件
  if (imageData.startsWith('data:image')) {
    const filename = saveBase64ToFile(imageData, prefix);
    return filename ? `/images/${filename}` : null;
  }

  // 如果是网络图片 URL，下载并保存
  if (imageData.startsWith('http://') || imageData.startsWith('https://')) {
    console.log(`[processImage] Downloading ${prefix}...`);
    const filename = await downloadImage(imageData, prefix);
    return filename ? `/images/${filename}` : null;
  }

  console.log(`[processImage] Unknown format for ${prefix}`);
  return null;
}
