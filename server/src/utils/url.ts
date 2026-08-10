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
