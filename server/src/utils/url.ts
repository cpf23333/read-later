/**
 * URL 标准化工具
 *
 * 与前端 utils/storage.ts 的 normalizeUrl 保持逻辑一致
 */

const TRACKING_PARAMS = [
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'fbclid',
  'gclid',
];

export function normalizeUrl(url: string): string {
  try {
    const urlObj = new URL(url);

    // 移除末尾斜杠
    let pathname = urlObj.pathname;
    if (pathname.length > 1 && pathname.endsWith('/')) {
      pathname = pathname.slice(0, -1);
    }

    // 忽略常见的 tracking 参数
    const searchParams = new URLSearchParams(urlObj.search);
    for (const param of TRACKING_PARAMS) {
      searchParams.delete(param);
    }
    const search = searchParams.toString();

    return `${urlObj.protocol}//${urlObj.hostname}${pathname}${search ? '?' + search : ''}`;
  } catch {
    return url.toLowerCase().trim();
  }
}

/**
 * 提取 URL 的主机名（域名），用于按收藏目标归类。
 * 非 http(s) 或非法 URL 返回 null。
 */
export function domainOf(url: string): string | null {
  try {
    const urlObj = new URL(url);
    if (urlObj.protocol !== 'http:' && urlObj.protocol !== 'https:') {
      return null;
    }
    const host = urlObj.hostname.toLowerCase();
    // www.example.com 和 example.com 通常指向同一服务，归为同一域名
    return host.startsWith('www.') ? host.slice(4) : host;
  } catch {
    return null;
  }
}

/**
 * 归一化为站点 origin（scheme://host[:port]）
 * 非 http(s) 或非法 URL 返回 null
 */
export function normalizeOrigin(url: string): string | null {
  try {
    const urlObj = new URL(url);
    if (urlObj.protocol !== 'http:' && urlObj.protocol !== 'https:') {
      return null;
    }
    return urlObj.origin;
  } catch {
    return null;
  }
}
