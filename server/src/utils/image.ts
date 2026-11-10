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

const ICO_PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** 从 ICO 文件中提取最大的 PNG 帧（现代 favicon 常见）。 */
function extractIcoPng(buffer: Buffer): Buffer | null {
  if (buffer.length < 6) return null;
  if (buffer.readUInt16LE(0) !== 0 || buffer.readUInt16LE(2) !== 1) return null;
  const count = buffer.readUInt16LE(4);
  let best: Buffer | null = null;
  for (let i = 0; i < count; i++) {
    const entry = 6 + i * 16;
    if (entry + 16 > buffer.length) break;
    const size = buffer.readUInt32LE(entry + 8);
    const offset = buffer.readUInt32LE(entry + 12);
    if (size === 0 || offset + size > buffer.length) continue;
    const frame = buffer.subarray(offset, offset + size);
    if (
      frame.length >= ICO_PNG_SIGNATURE.length &&
      frame.subarray(0, ICO_PNG_SIGNATURE.length).equals(ICO_PNG_SIGNATURE)
    ) {
      if (!best || frame.length > best.length) best = frame;
    }
  }
  return best;
}

/** 从 ICO 的 BMP 帧解码为 PNG（常见旧版 favicon）。 */
async function decodeIcoBmp(buffer: Buffer): Promise<Buffer | null> {
  if (buffer.length < 6) return null;
  if (buffer.readUInt16LE(0) !== 0 || buffer.readUInt16LE(2) !== 1) return null;
  const count = buffer.readUInt16LE(4);
  let best: { width: number; height: number; bitCount: number; frame: Buffer } | null =
    null;
  for (let i = 0; i < count; i++) {
    const entry = 6 + i * 16;
    if (entry + 16 > buffer.length) break;
    const width = buffer[entry] || 256;
    const height = buffer[entry + 1] || 256;
    const bitCount = buffer.readUInt16LE(entry + 6);
    const size = buffer.readUInt32LE(entry + 8);
    const offset = buffer.readUInt32LE(entry + 12);
    if (size === 0 || offset + size > buffer.length) continue;
    const frame = buffer.subarray(offset, offset + size);
    if (
      frame.length >= ICO_PNG_SIGNATURE.length &&
      frame.subarray(0, ICO_PNG_SIGNATURE.length).equals(ICO_PNG_SIGNATURE)
    ) {
      continue;
    }
    if (!best || width * height > best.width * best.height) {
      best = { width, height, bitCount, frame };
    }
  }
  if (!best) return null;

  const { frame, width, height, bitCount } = best;
  const headerSize = frame.readUInt32LE(0);
  if (headerSize < 40 || frame.length < headerSize) return null;
  const paletteCount = bitCount <= 8 ? 1 << bitCount : 0;
  const xorOffset = headerSize + paletteCount * 4;
  const rowSize = Math.floor((bitCount * width + 31) / 32) * 4;
  if (xorOffset + rowSize * height > frame.length) return null;
  const maskOffset = xorOffset + rowSize * height;
  const maskRowSize = Math.floor((width + 31) / 32) * 4;
  const rgba = Buffer.alloc(width * height * 4);
  const palette: number[][] = [];
  for (let i = 0; i < paletteCount; i++) {
    const p = headerSize + i * 4;
    if (p + 4 > frame.length) break;
    palette.push([frame[p + 2], frame[p + 1], frame[p], frame[p + 3]]);
  }

  for (let y = 0; y < height; y++) {
    const srcRow = xorOffset + (height - 1 - y) * rowSize;
    const dstRow = y * width * 4;
    for (let x = 0; x < width; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 255;
      if (bitCount === 32) {
        const p = srcRow + x * 4;
        b = frame[p];
        g = frame[p + 1];
        r = frame[p + 2];
        a = frame[p + 3];
      } else if (bitCount === 24) {
        const p = srcRow + x * 3;
        b = frame[p];
        g = frame[p + 1];
        r = frame[p + 2];
      } else if (bitCount === 8) {
        const color = palette[frame[srcRow + x]] ?? [0, 0, 0, 255];
        [r, g, b, a] = color;
      } else {
        return null;
      }

      if (maskOffset + maskRowSize * height <= frame.length) {
        const maskByte = frame[maskOffset + (height - 1 - y) * maskRowSize + (x >> 3)];
        if (maskByte !== undefined && (maskByte & (0x80 >> (x & 7))) !== 0) {
          a = 0;
        }
      }
      const p = dstRow + x * 4;
      rgba[p] = r;
      rgba[p + 1] = g;
      rgba[p + 2] = b;
      rgba[p + 3] = a;
    }
  }

  return sharp(rgba, { raw: { width, height, channels: 4 } }).png().toBuffer();
}

/**
 * 站点图标专用处理：统一转成 256px PNG，避免 ICO/WebP 等格式在客户端无法显示。
 */
export async function processSiteIcon(imageData: string): Promise<string | null> {
  try {
    let buffer: Buffer | null = null;

    if (imageData.startsWith('data:image')) {
      const match = imageData.match(/^data:image\/[\w.+-]+;base64,(.+)$/s);
      if (!match) return null;
      buffer = Buffer.from(match[1], 'base64');
    } else if (imageData.startsWith('http://') || imageData.startsWith('https://')) {
      if (!isValidImageUrl(imageData)) return null;
      const response = await fetch(imageData);
      if (!response.ok) return null;
      buffer = Buffer.from(await response.arrayBuffer());
    }
    if (!buffer || buffer.length === 0 || buffer.length > MAX_IMAGE_SIZE) {
      return null;
    }

    const pngFrame = extractIcoPng(buffer);
    if (pngFrame) {
      buffer = pngFrame;
    } else {
      const bmpPng = await decodeIcoBmp(buffer);
      if (bmpPng) buffer = bmpPng;
    }

    const png = await sharp(buffer)
      .trim({ threshold: 10 })
      .resize(256, 256, {
        fit: 'contain',
        background: { r: 0, g: 0, b: 0, alpha: 0 },
      })
      .png()
      .toBuffer();

    const filename = `${Date.now()}_site_icon_${Math.random()
      .toString(36)
      .substring(2, 9)}.png`;
    const filepath = path.join(IMAGES_DIR, filename);
    if (!isSafeFilePath(filename, IMAGES_DIR)) return null;
    fs.writeFileSync(filepath, png);
    return `/images/${filename}`;
  } catch (error) {
    console.error('[processSiteIcon] Failed:', (error as Error).message);
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
