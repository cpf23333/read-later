// 统一存储接口 - 直接同步到服务器

import { LinkItem, DeleteRecord } from './storage';
import { 
  apiGetLinks, 
  apiSearchLinks,
  apiAddLink, 
  apiDeleteLink, 
  apiGetTrash, 
  apiRestoreFromTrash, 
  apiPermanentlyDelete, 
  apiGetStats,
  apiGetDomainStats,
  apiGetAllDomains,
  apiExport,
  apiImport,
  apiUploadImage,
  getServerConfig,
  testServerConnection,
} from './apiStorage';

// hybridStorage.ts 只导出统一存储接口函数

// 检查服务器是否可用
export async function checkServerHealth(): Promise<boolean> {
  const config = await getServerConfig();
  if (!config.enabled || !config.url) {
    return false;
  }
  
  try {
    const result = await testServerConnection(config.url);
    return result.success;
  } catch {
    return false;
  }
}

// ===== 统一存储接口 =====

// 获取链接列表
export async function getLinks(
  page: number = 1,
  pageSize: number = 50,
  options?: { 
    sortBy?: 'createdAt' | 'title' | 'domain';
    sortDesc?: boolean;
    domain?: string;
    search?: string;
  }
): Promise<{ links: LinkItem[]; total: number }> {
  const sortBy = options?.sortBy === 'title' ? 'title' : 'created_at';
  const sortOrder = options?.sortDesc !== false ? 'desc' : 'asc';
  
  return await apiGetLinks(page, pageSize, {
    search: options?.search,
    domain: options?.domain,
    sortBy,
    sortOrder,
  });
}

// 辅助函数：上传图片到服务器
async function uploadImagesIfNeeded(link: LinkItem): Promise<LinkItem> {
  const updatedLink = { ...link };
  
  // 上传 nearbyImage（如果是 Base64）
  if (link.nearbyImage && link.nearbyImage.startsWith('data:image')) {
    try {
      const imageUrl = await apiUploadImage(link.nearbyImage, `nearby_${link.id}.png`);
      updatedLink.nearbyImage = imageUrl;
    } catch (error) {
      console.warn('[Storage] Failed to upload nearbyImage:', error);
    }
  }
  
  // 上传 screenshot（如果是 Base64）
  if (link.screenshot && link.screenshot.startsWith('data:image')) {
    try {
      const imageUrl = await apiUploadImage(link.screenshot, `screenshot_${link.id}.jpg`);
      updatedLink.screenshot = imageUrl;
    } catch (error) {
      console.warn('[Storage] Failed to upload screenshot:', error);
    }
  }
  
  return updatedLink;
}

// 添加链接
export async function addLink(link: Omit<LinkItem, 'id' | 'createdAt'>): Promise<LinkItem> {
  const item: LinkItem = {
    ...link,
    id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    createdAt: Date.now(),
  };
  
  // 上传图片到服务器
  const itemWithImages = await uploadImagesIfNeeded(item);
  
  // 保存到服务器
  await apiAddLink(itemWithImages);
  
  return itemWithImages;
}

// 删除链接
export async function deleteLink(id: string): Promise<{ success: boolean; record?: DeleteRecord }> {
  try {
    await apiDeleteLink(id);
    return { success: true };
  } catch (error) {
    console.error('[Storage] Delete failed:', error);
    return { success: false };
  }
}

// 从回收站还原
export async function restoreFromTrash(recordId: string): Promise<{ success: boolean; link?: LinkItem }> {
  try {
    const result = await apiRestoreFromTrash(recordId);
    return { success: true };
  } catch (error) {
    console.error('[Storage] Restore failed:', error);
    return { success: false };
  }
}

// 永久删除
export async function permanentlyDeleteFromTrash(recordId: string): Promise<boolean> {
  try {
    await apiPermanentlyDelete(recordId);
    return true;
  } catch (error) {
    console.error('[Storage] Permanent delete failed:', error);
    return false;
  }
}

// 获取回收站列表
export async function getTrashItems(): Promise<DeleteRecord[]> {
  return await apiGetTrash();
}

// 获取统计信息
export async function getStats(): Promise<{ linkCount: number; trashCount: number }> {
  return await apiGetStats();
}

// 检查链接是否已存在
export async function isLinkExists(url: string): Promise<boolean> {
  try {
    // 从服务器获取所有链接检查
    const { links } = await apiGetLinks(1, 1000);
    return links.some(link => link.url === url);
  } catch (error) {
    console.warn('[Storage] Failed to check link exists:', error);
    return false;
  }
}

// 获取域名统计
export async function getDomainStats(): Promise<{ domain: string; count: number }[]> {
  return await apiGetDomainStats();
}

// 获取所有域名
export async function getAllDomains(): Promise<string[]> {
  return await apiGetAllDomains();
}

// 搜索链接
export async function searchLinks(query: string): Promise<LinkItem[]> {
  return await apiSearchLinks(query);
}

// 导出所有链接
export async function exportLinks(): Promise<string> {
  const links = await apiExport();
  return JSON.stringify(links, null, 2);
}

// 导入链接
export async function importLinks(jsonString: string, mode: 'merge' | 'replace' = 'merge'): Promise<{ imported: number; skipped: number; total: number }> {
  let data: LinkItem[];
  try {
    data = JSON.parse(jsonString);
    if (!Array.isArray(data)) {
      throw new Error('Invalid format: expected an array');
    }
  } catch (error) {
    throw new Error('无效的JSON文件');
  }
  
  const result = await apiImport(data, mode);
  return {
    imported: result.imported,
    skipped: result.total - result.imported,
    total: result.total,
  };
}

// 获取链接数量
export async function getLinkCount(): Promise<number> {
  const stats = await apiGetStats();
  return stats.linkCount;
}
