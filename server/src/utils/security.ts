/**
 * 安全工具函数
 */

import path from 'path';

// 输入验证：ID 只允许字母数字和下划线
export function sanitizeId(id: string): string | null {
  if (typeof id !== 'string') return null;
  if (!/^[a-zA-Z0-9_]+$/.test(id)) return null;
  return id;
}

// 输入验证：搜索查询清理
export function sanitizeSearchQuery(query: string): string {
  if (typeof query !== 'string') return '';
  return query.slice(0, 200).replace(/[<>"']/g, '');
}

// 验证文件路径安全（防止路径遍历）
export function isSafeFilePath(filename: string, baseDir: string): boolean {
  const resolvedPath = path.resolve(baseDir, filename);
  const resolvedBase = path.resolve(baseDir);
  return resolvedPath.startsWith(resolvedBase);
}

// 验证图片 URL
export function isValidImageUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    // 只允许 http 和 https
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return false;
    }
    // 生产环境禁止访问私有 IP
    const hostname = parsed.hostname;
    if (
      hostname === 'localhost' ||
      hostname === '127.0.0.1' ||
      hostname.startsWith('192.168.') ||
      hostname.startsWith('10.') ||
      hostname.startsWith('172.')
    ) {
      if (process.env.NODE_ENV === 'production') {
        return false;
      }
    }
    return true;
  } catch {
    return false;
  }
}

// 允许的图片类型
export const ALLOWED_IMAGE_TYPES = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
] as const;

// 允许的图片扩展名
export const ALLOWED_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'] as const;

// 检查是否是允许的图片扩展名
export function isAllowedExtension(ext: string): boolean {
  return ALLOWED_EXTENSIONS.includes(ext.toLowerCase() as (typeof ALLOWED_EXTENSIONS)[number]);
}
