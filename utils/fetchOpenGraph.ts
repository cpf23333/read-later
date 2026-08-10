// 前端 Open Graph 图片抓取工具
// 在浏览器扩展环境中运行，可利用用户本地的 Tailscale/Clash 网络访问目标网站

export interface FetchImageResult {
  url: string;
  base64: string | null;
}

/**
 * 从页面 HTML 中提取 Open Graph 图片并下载为 base64
 */
export async function fetchOpenGraphImage(pageUrl: string): Promise<string | null> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);

    const response = await fetch(pageUrl, {
      method: 'GET',
      headers: {
        Accept: 'text/html,application/xhtml+xml',
      },
      signal: controller.signal,
      redirect: 'follow',
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.warn(`[fetchOpenGraphImage] HTTP ${response.status} for ${pageUrl}`);
      return null;
    }

    const contentType = response.headers.get('content-type') || '';
    if (!contentType.includes('text/html')) {
      return null;
    }

    const html = await response.text();
    if (!html || html.length > 2 * 1024 * 1024) {
      console.warn(`[fetchOpenGraphImage] HTML too large for ${pageUrl}`);
      return null;
    }

    // 提取 og:image / twitter:image / image_src（支持属性顺序互换）
    const ogImage =
      html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i)?.[1] ||
      html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']/i)?.[1];

    const twitterImage =
      html.match(/<meta[^>]*name=["']twitter:image["'][^>]*content=["']([^"']+)["']/i)?.[1] ||
      html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*name=["']twitter:image["']/i)?.[1];

    const imageSrc = html.match(/<link[^>]*rel=["']image_src["'][^>]*href=["']([^"']+)["']/i)?.[1];

    const imageUrl = ogImage || twitterImage || imageSrc;
    if (!imageUrl) {
      return null;
    }

    // 解析相对 URL
    let absoluteUrl = imageUrl;
    if (!absoluteUrl.startsWith('http://') && !absoluteUrl.startsWith('https://')) {
      absoluteUrl = new URL(imageUrl, pageUrl).href;
    }

    // 下载图片并转为 base64
    return await downloadImageAsBase64(absoluteUrl);
  } catch (error) {
    console.warn('[fetchOpenGraphImage] Failed for', pageUrl, (error as Error).message);
    return null;
  }
}

/**
 * 下载网络图片并转为 base64 data URL
 */
async function downloadImageAsBase64(imageUrl: string): Promise<string | null> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const response = await fetch(imageUrl, {
      method: 'GET',
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.warn(`[downloadImageAsBase64] HTTP ${response.status}`);
      return null;
    }

    const contentType = response.headers.get('content-type') || '';
    if (!contentType.startsWith('image/')) {
      console.warn(`[downloadImageAsBase64] Not an image: ${contentType}`);
      return null;
    }

    const blob = await response.blob();
    if (blob.size > 5 * 1024 * 1024) {
      console.warn(`[downloadImageAsBase64] Image too large: ${blob.size}`);
      return null;
    }

    return await blobToBase64(blob);
  } catch (error) {
    console.warn('[downloadImageAsBase64] Failed:', (error as Error).message);
    return null;
  }
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error('FileReader failed'));
    reader.readAsDataURL(blob);
  });
}

/**
 * 限制并发数量的异步工具
 */
export async function withConcurrencyLimit<T>(
  items: T[],
  limit: number,
  fn: (item: T, index: number) => Promise<void>
): Promise<void> {
  let index = 0;

  async function worker(): Promise<void> {
    while (index < items.length) {
      const i = index++;
      try {
        await fn(items[i]!, i);
      } catch {
        // 单条失败不影响其他
      }
    }
  }

  const workers = Array(Math.min(limit, items.length))
    .fill(null)
    .map(() => worker());
  await Promise.all(workers);
}
