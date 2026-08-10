/**
 * 图片处理工具
 */

import fs from 'fs';
import path from 'path';
import sharp from 'sharp';
import { ALLOWED_IMAGE_TYPES, isSafeFilePath, isValidImageUrl } from './security.ts';

// 从环境变量获取配置
const MAX_IMAGE_SIZE = parseInt(process.env.MAX_IMAGE_SIZE_MB || '10', 10) * 1024 * 1024;

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
      if (!ALLOWED_IMAGE_TYPES.includes(mimeType as (typeof ALLOWED_IMAGE_TYPES)[number])) {
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
    if (!ALLOWED_IMAGE_TYPES.some((type) => contentType.includes(type.replace('image/', '')))) {
      console.warn(`[downloadImage] Unsupported image type: ${contentType}`);
      return null;
    }

    const buffer = Buffer.from(await response.arrayBuffer());

    if (buffer.length > MAX_IMAGE_SIZE) {
      console.warn(`[downloadImage] Too large: ${buffer.length} bytes`);
      return null;
    }

    const ext = prefix === 'screenshot' ? 'jpg' : contentType.includes('png') ? 'png' : 'jpg';

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
export async function processImage(
  imageData: string | undefined,
  prefix: string
): Promise<string | null> {
  if (!imageData) return null;

  console.log(`[processImage] ${prefix}:`, imageData.substring(0, 60) + '...');

  // 如果已经是路径，直接返回
  if (imageData.startsWith('/images/')) {
    return imageData;
  }

  let filename: string | null = null;

  // 如果是 Base64，保存为文件
  if (imageData.startsWith('data:image')) {
    filename = saveBase64ToFile(imageData, prefix);
  }

  // 如果是网络图片 URL，下载并保存
  if (imageData.startsWith('http://') || imageData.startsWith('https://')) {
    console.log(`[processImage] Downloading ${prefix}...`);
    filename = await downloadImage(imageData, prefix);
  }

  if (!filename) {
    console.log(`[processImage] Unknown format for ${prefix}`);
    return null;
  }

  // 异步生成缩略图（失败不影响主流程）
  createThumbnail(filename).catch((error) => {
    console.warn('[processImage] Failed to create thumbnail:', (error as Error).message);
  });

  return `/images/${filename}`;
}

/**
 * 生成缩略图
 */
async function createThumbnail(originalFilename: string): Promise<string | null> {
  if (!IMAGES_DIR) return null;

  const inputPath = path.join(IMAGES_DIR, originalFilename);
  if (!fs.existsSync(inputPath)) return null;

  const thumbsDir = path.join(IMAGES_DIR, 'thumbs');
  if (!fs.existsSync(thumbsDir)) {
    fs.mkdirSync(thumbsDir, { recursive: true });
  }

  const thumbName = `${path.parse(originalFilename).name}_thumb.jpg`;
  const thumbPath = path.join(thumbsDir, thumbName);

  await sharp(inputPath)
    .resize(320, 240, { fit: 'cover', withoutEnlargement: true })
    .jpeg({ quality: 80, progressive: true })
    .toFile(thumbPath);

  console.log(`[createThumbnail] Created: ${thumbName}`);
  return thumbName;
}

/**
 * 根据原图路径获取缩略图路径
 */
export function getThumbPath(originalPath: string): string | null {
  if (!originalPath || originalPath.startsWith('/images/deleted/')) return null;
  if (!originalPath.startsWith('/images/')) return null;

  const filename = path.basename(originalPath);
  const thumbName = `${path.parse(filename).name}_thumb.jpg`;
  return `/images/thumbs/${thumbName}`;
}

/**
 * 根据原图 URL 获取缩略图 URL
 */
export function getThumbUrl(originalUrl: string): string | null {
  try {
    const url = new URL(originalUrl);
    const thumbPath = getThumbPath(url.pathname);
    if (!thumbPath) return null;
    url.pathname = thumbPath;
    return url.toString();
  } catch {
    return null;
  }
}

/**
 * 移动图片到回收站目录
 */
export function moveImageToTrash(imgPath: string): void {
  if (!imgPath || !imgPath.startsWith('/images/') || imgPath.startsWith('/images/deleted/')) return;
  if (!IMAGES_DIR) return;

  const filename = path.basename(imgPath);
  const src = path.join(IMAGES_DIR, filename);
  const dest = path.join(IMAGES_DIR, 'deleted', filename);
  if (fs.existsSync(src)) {
    fs.renameSync(src, dest);
  }

  // 同时移动缩略图
  const thumbName = `${path.parse(filename).name}_thumb.jpg`;
  const thumbSrc = path.join(IMAGES_DIR, 'thumbs', thumbName);
  const thumbDest = path.join(IMAGES_DIR, 'deleted', thumbName);
  if (fs.existsSync(thumbSrc)) {
    fs.renameSync(thumbSrc, thumbDest);
  }
}

/**
 * 从回收站目录还原图片
 */
export function restoreImageFromTrash(imgPath: string): void {
  if (!imgPath || !imgPath.startsWith('/images/')) return;
  if (!IMAGES_DIR) return;

  const filename = path.basename(imgPath);
  const src = path.join(IMAGES_DIR, 'deleted', filename);
  const dest = path.join(IMAGES_DIR, filename);
  if (fs.existsSync(src)) {
    fs.renameSync(src, dest);
  }

  // 同时还原缩略图
  const thumbName = `${path.parse(filename).name}_thumb.jpg`;
  const thumbSrc = path.join(IMAGES_DIR, 'deleted', thumbName);
  const thumbDest = path.join(IMAGES_DIR, 'thumbs', thumbName);
  if (fs.existsSync(thumbSrc)) {
    const thumbsDir = path.join(IMAGES_DIR, 'thumbs');
    if (!fs.existsSync(thumbsDir)) {
      fs.mkdirSync(thumbsDir, { recursive: true });
    }
    fs.renameSync(thumbSrc, thumbDest);
  }
}

/**
 * 永久删除回收站中的图片文件
 */
export function deleteImageFile(imgPath: string): void {
  if (!imgPath || !imgPath.startsWith('/images/')) return;
  if (!IMAGES_DIR) return;

  const filename = path.basename(imgPath);
  const filePath = path.join(IMAGES_DIR, 'deleted', filename);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }

  // 同时删除缩略图
  const thumbName = `${path.parse(filename).name}_thumb.jpg`;
  const thumbPath = path.join(IMAGES_DIR, 'deleted', thumbName);
  if (fs.existsSync(thumbPath)) {
    fs.unlinkSync(thumbPath);
  }
}
