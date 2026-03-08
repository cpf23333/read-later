// 类型定义模块 - 链接数据类型

export interface LinkItem {
  id: string;
  url: string;
  title: string;
  nearbyImage: string | null; // base64 或 URL
  screenshot: string | null;  // base64
  sourcePage: string;
  createdAt: number;
  customData?: any;
}

export interface CustomJsConfig {
  id: string;
  name: string;
  code: string;
  enabled: boolean;
}

export interface DeleteRecord {
  id: string;  // delete_{url} 格式
  linkId: string;  // 原始链接ID
  url: string;
  title: string;
  sourcePage: string;
  createdAt: number;
  deletedAt: number;
  normalizedUrl: string;
  nearbyImage: string | null;
  screenshot: string | null;
  customData?: any;
}

export interface ImportResult {
  imported: number;
  skipped: number;
  total: number;
}

// URL标准化函数
export function normalizeUrl(url: string): string {
  try {
    const urlObj = new URL(url);
    // 移除末尾斜杠
    let pathname = urlObj.pathname;
    if (pathname.length > 1 && pathname.endsWith('/')) {
      pathname = pathname.slice(0, -1);
    }
    // 忽略hash
    // 可选：忽略常见的tracking参数
    const trackingParams = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'fbclid', 'gclid'];
    const searchParams = new URLSearchParams(urlObj.search);
    trackingParams.forEach(param => searchParams.delete(param));
    const search = searchParams.toString();
    
    return `${urlObj.protocol}//${urlObj.hostname}${pathname}${search ? '?' + search : ''}`;
  } catch {
    return url.toLowerCase().trim();
  }
}
