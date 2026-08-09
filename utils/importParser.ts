// 导入文件解析工具 - 支持 JSON 备份和 HTML 书签格式

export interface ParsedLink {
  url: string;
  title: string;
  sourcePage?: string;
  nearbyImage?: string | null;
  screenshot?: string | null;
  createdAt?: number;
}

export interface ParseResult {
  links: ParsedLink[];
  format: 'json' | 'html';
}

/**
 * 解析导入文件，自动识别 JSON 或 HTML 书签格式
 */
export async function parseImportFile(file: File): Promise<ParseResult> {
  const text = await file.text();
  const trimmed = text.trim();
  const ext = file.name.split('.').pop()?.toLowerCase();

  // 优先根据内容特征判断
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    return { links: parseJson(text), format: 'json' };
  }

  if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<')) {
    return { links: parseHtmlBookmarks(text), format: 'html' };
  }

  // 根据扩展名判断
  if (ext === 'json') {
    return { links: parseJson(text), format: 'json' };
  }

  if (ext === 'html' || ext === 'htm') {
    return { links: parseHtmlBookmarks(text), format: 'html' };
  }

  throw new Error('不支持的文件格式，请上传 .json 备份文件或 .html 书签文件');
}

function parseJson(text: string): ParsedLink[] {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error('JSON 解析失败：文件内容不是有效的 JSON');
  }

  let links: unknown[];

  if (Array.isArray(data)) {
    links = data;
  } else if (data && typeof data === 'object' && 'links' in data && Array.isArray((data as any).links)) {
    links = (data as any).links;
  } else {
    throw new Error('JSON 格式错误：未找到链接数组（期望顶层为数组或包含 links 字段的对象）');
  }

  const parsed = links
    .map((item: any): ParsedLink | null => {
      if (!item || typeof item !== 'object') return null;
      const url = String(item.url || '');
      if (!url || (!url.startsWith('http://') && !url.startsWith('https://'))) {
        return null;
      }
      return {
        url,
        title: String(item.title || item.name || '无标题'),
        sourcePage: String(item.sourcePage || item.source_page || ''),
        nearbyImage: item.nearbyImage || item.nearby_image || null,
        screenshot: item.screenshot || null,
        createdAt: typeof item.createdAt === 'number' ? item.createdAt : typeof item.created_at === 'number' ? item.created_at : undefined,
      };
    })
    .filter((link): link is ParsedLink => link !== null);

  if (parsed.length === 0) {
    throw new Error('未从 JSON 文件中解析出有效链接');
  }

  return parsed;
}

function parseHtmlBookmarks(html: string): ParsedLink[] {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, 'text/html');

  // 解析错误检查
  const parseError = doc.querySelector('parsererror');
  if (parseError) {
    throw new Error('HTML 解析失败：文件内容不是有效的 HTML');
  }

  const links: ParsedLink[] = [];

  // Netscape Bookmark File Format: <DT><A HREF="url" ADD_DATE="...">title</A>
  // Chrome/Firefox 导出的书签都使用这个格式
  const anchors = doc.querySelectorAll('dt > a[href], dl > a[href], a[href]');

  anchors.forEach((a) => {
    const href = a.getAttribute('href');
    if (!href) return;

    // 过滤掉非 HTTP 链接和浏览器内部链接
    if (
      href.startsWith('javascript:') ||
      href.startsWith('place:') ||
      href.startsWith('about:') ||
      href.startsWith('chrome://') ||
      href.startsWith('edge://') ||
      href.startsWith('moz-extension://') ||
      href.startsWith('chrome-extension://')
    ) {
      return;
    }

    const addDate = a.getAttribute('add_date');
    const createdAt = addDate ? parseInt(addDate, 10) * 1000 : undefined;

    links.push({
      url: href,
      title: a.textContent?.trim() || '无标题',
      sourcePage: '',
      nearbyImage: null,
      screenshot: null,
      createdAt,
    });
  });

  if (links.length === 0) {
    throw new Error('未从 HTML 书签文件中解析出有效链接（请确保是浏览器导出的书签文件）');
  }

  return links;
}
