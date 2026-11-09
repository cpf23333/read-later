/**
 * 图片 URL 工具
 */

/**
 * 根据原图 URL 生成缩略图 URL
 * 原图路径如 /images/abc.png，对应缩略图 /images/thumbs/abc_thumb.jpg
 */
export function getThumbUrl(originalUrl: string | null | undefined): string | null {
  if (!originalUrl) return null;

  try {
    const url = new URL(originalUrl);
    const match = url.pathname.match(/^\/images\/(.+)$/);
    if (!match) return null;

    const filename = match[1];
    if (!filename) return null;

    const baseName = filename.replace(/\.[^.]+$/, '');
    url.pathname = `/images/thumbs/${baseName}_thumb.jpg`;

    return url.toString();
  } catch {
    return null;
  }
}

/**
 * 处理图片加载失败：如果 src 是缩略图则回退到原图，否则返回 null
 */
export function handleThumbError(
  event: Event,
  originalUrl: string | null | undefined
): void {
  const img = event.target as HTMLImageElement;
  if (!img || !originalUrl) return;

  const thumbUrl = getThumbUrl(originalUrl);
  // 如果当前已经是原图，或者没有缩略图，不再处理
  if (!thumbUrl || img.src === originalUrl) return;

  // 如果当前是缩略图且加载失败，回退到原图
  if (img.src === thumbUrl) {
    img.src = originalUrl;
    // 移除事件监听，避免原图也失败时循环
    img.onerror = null;
  }
}
