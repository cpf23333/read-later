// HTTP API 存储适配器 - 连接 SQLite 后端

import { LinkItem, DeleteRecord } from './storage';

export interface ServerConfig {
  enabled: boolean;
  url: string;
}

const CONFIG_KEY = 'server_config';

// 获取服务器配置
export async function getServerConfig(): Promise<ServerConfig> {
  const result = await browser.storage.sync.get(CONFIG_KEY);
  const config = result[CONFIG_KEY];
  if (config && typeof config === 'object' && 'enabled' in config && 'url' in config) {
    return config as ServerConfig;
  }
  return { enabled: false, url: '' };
}

// 保存服务器配置
export async function saveServerConfig(config: ServerConfig): Promise<void> {
  await browser.storage.sync.set({ [CONFIG_KEY]: config });
}

// 测试连接
export async function testServerConnection(url: string): Promise<{ success: boolean; message: string }> {
  try {
    const response = await fetch(`${url}/api/health`, { method: 'GET' });
    if (response.ok) {
      return { success: true, message: '连接成功' };
    } else {
      return { success: false, message: `连接失败: HTTP ${response.status}` };
    }
  } catch (error) {
    return { success: false, message: `连接失败: ${error instanceof Error ? error.message : '未知错误'}` };
  }
}

// HTTP 请求封装
async function apiRequest<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    throw new Error('服务器未配置');
  }
  
  const response = await fetch(`${config.url}${endpoint}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  
  if (!response.ok) {
    throw new Error(`API 错误: ${response.status}`);
  }
  
  const result = await response.json();
  if (!result.success) {
    throw new Error(result.error || '未知错误');
  }
  
  return result.data;
}

// 转换数据库格式到 LinkItem
function dbToLinkItem(item: any): LinkItem {
  return {
    id: item.id,
    url: item.url,
    title: item.title,
    nearbyImage: item.nearby_image,
    screenshot: item.screenshot,
    sourcePage: item.source_page,
    createdAt: item.created_at,
    customData: item.custom_data ? JSON.parse(item.custom_data) : undefined,
  };
}

// ===== 链接 API =====

export async function apiGetLinks(page: number = 1, pageSize: number = 50): Promise<{ links: LinkItem[]; total: number }> {
  const data = await apiRequest<{ data: any[]; total: number }>(`/api/links?page=${page}&pageSize=${pageSize}`);
  return {
    links: data.data.map(dbToLinkItem),
    total: data.total,
  };
}

export async function apiAddLink(link: LinkItem): Promise<void> {
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

export async function apiBatchAddLinks(links: LinkItem[]): Promise<void> {
  await apiRequest('/api/links/batch', {
    method: 'POST',
    body: JSON.stringify({ links }),
  });
}

// ===== 回收站 API =====

export async function apiGetTrash(): Promise<DeleteRecord[]> {
  const data = await apiRequest<any[]>('/api/trash');
  return data.map(item => ({
    id: item.id,
    linkId: item.link_id,
    url: item.url,
    title: item.title,
    nearbyImage: item.nearby_image,
    screenshot: item.screenshot,
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
  const response = await fetch(`${config.url}/api/upload`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
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

// ===== 导入/导出 =====

export async function apiExport(): Promise<LinkItem[]> {
  const data = await apiRequest<any[]>('/api/export');
  return data.map(dbToLinkItem);
}

export async function apiImport(links: LinkItem[], mode: 'merge' | 'replace' = 'merge'): Promise<{ imported: number; total: number }> {
  return await apiRequest<{ imported: number; total: number }>('/api/import', {
    method: 'POST',
    body: JSON.stringify({ links, mode }),
  });
}

// 检查是否使用服务器
export async function isUsingServer(): Promise<boolean> {
  const config = await getServerConfig();
  return config.enabled && !!config.url;
}
