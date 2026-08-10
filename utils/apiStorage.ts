// HTTP API 存储适配器 - 连接 SQLite 后端

import { type LinkItem, type DeleteRecord, type CustomJsConfig, type ImportResult, type ExportTask } from './storage';

export interface ServerConfig {
  enabled: boolean;
  url: string;
  apiKey: string;
}

const CONFIG_KEY = 'server_config';
const CUSTOM_JS_KEY = 'custom_js_configs';

// 获取服务器配置
export async function getServerConfig(): Promise<ServerConfig> {
  const result = await browser.storage.sync.get(CONFIG_KEY);
  const config = result[CONFIG_KEY];
  if (config && typeof config === 'object' && 'enabled' in config && 'url' in config) {
    return config as ServerConfig;
  }
  return { enabled: false, url: '', apiKey: '' };
}

// 保存服务器配置
export async function saveServerConfig(config: ServerConfig): Promise<void> {
  await browser.storage.sync.set({ [CONFIG_KEY]: config });
}

// 测试连接
export async function testServerConnection(
  url: string,
  apiKey?: string
): Promise<{ success: boolean; message: string }> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000); // 5秒超时

    const headers: Record<string, string> = {};
    if (apiKey) {
      headers['Authorization'] = `Bearer ${apiKey}`;
    }

    const response = await fetch(`${url}/api/health`, {
      method: 'GET',
      signal: controller.signal,
      headers,
    });

    clearTimeout(timeoutId);

    if (response.ok) {
      return { success: true, message: '连接成功' };
    } else {
      return { success: false, message: `连接失败: HTTP ${response.status}` };
    }
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      return { success: false, message: '连接超时' };
    }
    return {
      success: false,
      message: `连接失败: ${error instanceof Error ? error.message : '未知错误'}`,
    };
  }
}

// HTTP 请求封装
async function apiRequest<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    throw new Error('服务器未配置');
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000); // 10秒超时

  try {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>),
    };

    // 添加 API Key 鉴权头
    if (config.apiKey) {
      headers['Authorization'] = `Bearer ${config.apiKey}`;
    }

    const response = await fetch(`${config.url}${endpoint}`, {
      ...options,
      signal: controller.signal,
      headers,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`API 错误: ${response.status}`);
    }

    const result = await response.json();
    if (!result.success) {
      throw new Error(result.error || '未知错误');
    }

    return result.data;
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error('请求超时');
    }
    throw error;
  }
}

// 转换数据库格式到 LinkItem
async function dbToLinkItem(item: any): Promise<LinkItem> {
  const config = await getServerConfig();
  const baseUrl = config.url || '';

  // 辅助函数：确保图片路径是完整URL
  const resolveImageUrl = (imgPath: string | null): string | null => {
    if (!imgPath) return null;
    // 如果已经是完整URL，直接返回
    if (imgPath.startsWith('http://') || imgPath.startsWith('https://')) {
      return imgPath;
    }
    // 如果是相对路径，拼接 baseUrl
    if (imgPath.startsWith('/')) {
      return `${baseUrl}${imgPath}`;
    }
    return imgPath;
  };

  const result = {
    id: item.id,
    url: item.url,
    title: item.title,
    nearbyImage: resolveImageUrl(item.nearby_image),
    screenshot: resolveImageUrl(item.screenshot),
    sourcePage: item.source_page,
    createdAt: item.created_at,
    customData: item.custom_data ? JSON.parse(item.custom_data) : undefined,
  };

  console.log('[dbToLinkItem] Converted:', {
    url: result.url,
    nearbyImage: result.nearbyImage,
    screenshot: result.screenshot,
  });

  return result;
}

// ===== 链接 API =====

export async function apiGetLinks(
  page: number = 1,
  pageSize: number = 50,
  options?: {
    search?: string;
    domain?: string;
    sortBy?: 'created_at' | 'title';
    sortOrder?: 'asc' | 'desc';
  }
): Promise<{ links: LinkItem[]; total: number }> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    throw new Error('服务器未配置');
  }

  let url = `${config.url}/api/links?page=${page}&pageSize=${pageSize}`;
  if (options?.search) url += `&search=${encodeURIComponent(options.search)}`;
  if (options?.domain) url += `&domain=${encodeURIComponent(options.domain)}`;
  if (options?.sortBy) url += `&sortBy=${options.sortBy}`;
  if (options?.sortOrder) url += `&sortOrder=${options.sortOrder}`;

  const headers: Record<string, string> = {};
  if (config.apiKey) {
    headers['Authorization'] = `Bearer ${config.apiKey}`;
  }

  const response = await fetch(url, { headers });
  if (!response.ok) {
    throw new Error(`API 错误: ${response.status}`);
  }

  const result = await response.json();
  if (!result.success) {
    throw new Error(result.error || '未知错误');
  }

  const links = await Promise.all(result.data.map(dbToLinkItem));
  return {
    links,
    total: result.total,
  };
}

export async function apiSearchLinks(query: string): Promise<LinkItem[]> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    throw new Error('服务器未配置');
  }

  const headers: Record<string, string> = {};
  if (config.apiKey) {
    headers['Authorization'] = `Bearer ${config.apiKey}`;
  }

  const response = await fetch(`${config.url}/api/search?q=${encodeURIComponent(query)}`, {
    headers,
  });
  if (!response.ok) {
    throw new Error(`API 错误: ${response.status}`);
  }

  const result = await response.json();
  if (!result.success) {
    throw new Error(result.error || '未知错误');
  }

  return await Promise.all(result.data.map(dbToLinkItem));
}

export async function apiAddLink(link: LinkItem): Promise<void> {
  console.log('[apiAddLink] Sending link to server:', {
    url: link.url,
    nearbyImage: link.nearbyImage ? `${link.nearbyImage.substring(0, 50)}...` : null,
    screenshot: link.screenshot ? `${link.screenshot.substring(0, 50)}...` : null,
  });
  await apiRequest('/api/links', {
    method: 'POST',
    body: JSON.stringify({
      id: link.id,
      url: link.url,
      title: link.title,
      nearby_image: link.nearbyImage,
      screenshot: link.screenshot,
      source_page: link.sourcePage,
      created_at: link.createdAt,
      custom_data: link.customData,
    }),
  });
}

export async function apiDeleteLink(id: string): Promise<void> {
  await apiRequest(`/api/links/${id}`, { method: 'DELETE' });
}

export async function apiBatchAddLinks(
  links: LinkItem[]
): Promise<{ count: number; total: number; failed: number }> {
  return await apiRequest<{ count: number; total: number; failed: number }>('/api/links/batch', {
    method: 'POST',
    body: JSON.stringify({ links }),
  });
}

export async function apiCheckLinkExists(
  url: string
): Promise<{ exists: boolean; link?: LinkItem }> {
  const result = await apiRequest<{ exists: boolean; link?: any }>(
    `/api/links/exists?url=${encodeURIComponent(url)}`
  );
  return {
    exists: result.exists,
    link: result.link ? await dbToLinkItem(result.link) : undefined,
  };
}

export async function apiCheckExistingUrls(urls: string[]): Promise<string[]> {
  return await apiRequest<string[]>('/api/links/check-batch', {
    method: 'POST',
    body: JSON.stringify({ urls }),
  });
}

// ===== 回收站 API =====

export async function apiGetTrash(): Promise<DeleteRecord[]> {
  const data = await apiRequest<any[]>('/api/trash');
  const config = await getServerConfig();
  const baseUrl = config.url || '';

  // 辅助函数：确保图片路径是完整URL
  const resolveImageUrl = (imgPath: string | null): string | null => {
    if (!imgPath) return null;
    if (imgPath.startsWith('http://') || imgPath.startsWith('https://')) {
      return imgPath;
    }
    if (imgPath.startsWith('/')) {
      return `${baseUrl}${imgPath}`;
    }
    return imgPath;
  };

  return data.map((item) => ({
    id: item.id,
    linkId: item.link_id,
    url: item.url,
    title: item.title,
    nearbyImage: resolveImageUrl(item.nearby_image),
    screenshot: resolveImageUrl(item.screenshot),
    sourcePage: item.source_page,
    createdAt: item.created_at,
    deletedAt: item.deleted_at,
    normalizedUrl: item.url,
    customData: item.custom_data ? JSON.parse(item.custom_data) : undefined,
  }));
}

export async function apiRestoreFromTrash(id: string): Promise<{ newId: string }> {
  return await apiRequest(`/api/trash/${id}/restore`, { method: 'POST' });
}

export async function apiPermanentlyDelete(id: string): Promise<void> {
  await apiRequest(`/api/trash/${id}`, { method: 'DELETE' });
}

// ===== 图片上传 =====

export async function apiUploadImage(base64Image: string, filename?: string): Promise<string> {
  const config = await getServerConfig();
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (config.apiKey) {
    headers['Authorization'] = `Bearer ${config.apiKey}`;
  }

  const response = await fetch(`${config.url}/api/upload`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ image: base64Image, filename }),
  });

  if (!response.ok) throw new Error('上传失败');
  const result = await response.json();
  if (!result.success) throw new Error(result.error);

  return `${config.url}${result.data.url}`;
}

// ===== 统计 =====

export async function apiGetStats(): Promise<{ linkCount: number; trashCount: number }> {
  return await apiRequest<{ linkCount: number; trashCount: number }>('/api/stats');
}

export async function apiGetDomainStats(): Promise<{ domain: string; count: number }[]> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    throw new Error('服务器未配置');
  }

  const headers: Record<string, string> = {};
  if (config.apiKey) {
    headers['Authorization'] = `Bearer ${config.apiKey}`;
  }

  const response = await fetch(`${config.url}/api/domains`, { headers });
  if (!response.ok) {
    throw new Error(`API 错误: ${response.status}`);
  }

  const result = await response.json();
  if (!result.success) {
    throw new Error(result.error || '未知错误');
  }

  return result.data;
}

export async function apiGetAllDomains(): Promise<string[]> {
  const stats = await apiGetDomainStats();
  return stats.map((s) => s.domain).sort();
}

// ===== 导入/导出 =====

export async function apiExport(): Promise<LinkItem[]> {
  const data = await apiRequest<any[]>('/api/export');
  return await Promise.all(data.map(dbToLinkItem));
}

export async function apiImport(
  links: LinkItem[],
  mode: 'merge' | 'replace' = 'merge'
): Promise<{ imported: number; total: number }> {
  return await apiRequest<{ imported: number; total: number }>('/api/import', {
    method: 'POST',
    body: JSON.stringify({ links, mode }),
  });
}

// ===== 导出任务 =====

export async function apiCreateExport(): Promise<{ taskId: string; status: string }> {
  return await apiRequest<{ taskId: string; status: string }>('/api/exports', {
    method: 'POST',
  });
}

export async function apiGetExports(): Promise<ExportTask[]> {
  const data = await apiRequest<any[]>('/api/exports');
  return data.map((item) => ({
    id: item.id,
    status: item.status,
    createdAt: item.created_at,
    completedAt: item.completed_at,
    filename: item.filename,
    fileSize: item.file_size,
    error: item.error,
  }));
}

export async function apiDownloadExport(id: string): Promise<Blob> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    throw new Error('服务器未配置');
  }

  const headers: Record<string, string> = {};
  if (config.apiKey) {
    headers['Authorization'] = `Bearer ${config.apiKey}`;
  }

  const response = await fetch(`${config.url}/api/exports/${id}/download`, { headers });
  if (!response.ok) {
    throw new Error(`下载失败: ${response.status}`);
  }

  return await response.blob();
}

export async function apiDeleteExport(id: string): Promise<void> {
  await apiRequest(`/api/exports/${id}`, { method: 'DELETE' });
}

// 检查是否使用服务器
export async function isUsingServer(): Promise<boolean> {
  const config = await getServerConfig();
  return config.enabled && !!config.url;
}

// ===== 自定义 JS 配置（使用 browser.storage）=====

export async function getCustomJsConfigs(): Promise<CustomJsConfig[]> {
  const result = await browser.storage.sync.get(CUSTOM_JS_KEY);
  const configs = result[CUSTOM_JS_KEY];
  return Array.isArray(configs) ? configs : [];
}

export async function saveCustomJsConfig(config: CustomJsConfig): Promise<void> {
  const configs = await getCustomJsConfigs();
  const index = configs.findIndex((c) => c.id === config.id);

  if (index >= 0) {
    configs[index] = config;
  } else {
    configs.push(config);
  }

  await browser.storage.sync.set({ [CUSTOM_JS_KEY]: configs });
}

export async function deleteCustomJsConfig(id: string): Promise<void> {
  const configs = await getCustomJsConfigs();
  const filtered = configs.filter((c) => c.id !== id);
  await browser.storage.sync.set({ [CUSTOM_JS_KEY]: filtered });
}

export async function getEnabledCustomJsConfig(): Promise<CustomJsConfig | null> {
  const configs = await getCustomJsConfigs();
  return configs.find((c) => c.enabled) || null;
}
