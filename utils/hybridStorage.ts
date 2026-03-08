// 混合存储模块 - 优先服务器，离线时本地暂存，恢复后自动同步

import { LinkItem, DeleteRecord, addLink as localAddLink, getLinks as localGetLinks, deleteLink as localDeleteLink, restoreFromTrash as localRestoreFromTrash, permanentlyDeleteFromTrash as localPermanentlyDeleteFromTrash, getTrashItems as localGetTrashItems, getLinkCount as localGetLinkCount, isLinkExists as localIsLinkExists } from './storage';
import { apiGetLinks, apiAddLink, apiDeleteLink, apiGetTrash, apiRestoreFromTrash, apiPermanentlyDelete, apiGetStats, isUsingServer, testServerConnection as apiTestServerConnection, getServerConfig as apiGetServerConfig, apiBatchAddLinks } from './apiStorage';

// 重新导出配置函数（带 Hybrid 后缀避免冲突）
export { getServerConfig as getServerConfigHybrid, saveServerConfig as saveServerConfigHybrid, testServerConnection as testServerConnectionHybrid } from './apiStorage';

// 同步状态
interface SyncState {
  isOnline: boolean;
  lastSyncTime: number;
  pendingCount: number;
}

const SYNC_STATE_KEY = 'sync_state';
const PENDING_SYNC_KEY = 'pending_sync';

// 获取同步状态
async function getSyncState(): Promise<SyncState> {
  const result = await browser.storage.local.get([SYNC_STATE_KEY]);
  const state = result[SYNC_STATE_KEY];
  if (state && typeof state === 'object' && 'isOnline' in state) {
    return state as SyncState;
  }
  return { isOnline: false, lastSyncTime: 0, pendingCount: 0 };
}

// 保存同步状态
async function saveSyncState(state: Partial<SyncState>): Promise<void> {
  const current = await getSyncState();
  await browser.storage.local.set({ 
    [SYNC_STATE_KEY]: { ...current, ...state } 
  });
}

// 获取待同步项目
async function getPendingItems(): Promise<PendingItem[]> {
  const result = await browser.storage.local.get([PENDING_SYNC_KEY]);
  const items = result[PENDING_SYNC_KEY];
  if (Array.isArray(items)) {
    return items;
  }
  return [];
}

// 添加待同步项目
async function addPendingItem(item: PendingItem): Promise<void> {
  const items = await getPendingItems();
  items.push({ ...item, timestamp: Date.now() });
  await browser.storage.local.set({ [PENDING_SYNC_KEY]: items });
  await updatePendingCount();
}

// 移除已同步项目
async function removePendingItems(ids: string[]): Promise<void> {
  const items = await getPendingItems();
  const filtered = items.filter(item => !ids.includes(item.id));
  await browser.storage.local.set({ [PENDING_SYNC_KEY]: filtered });
  await updatePendingCount();
}

// 更新待同步计数
async function updatePendingCount(): Promise<void> {
  const items = await getPendingItems();
  await saveSyncState({ pendingCount: items.length });
}

// 待同步项目类型
interface PendingItem {
  id: string;
  type: 'add' | 'delete' | 'restore' | 'permanent_delete';
  data?: any;
  timestamp: number;
}

// 检查服务器是否可用
export async function checkServerHealthHybrid(): Promise<boolean> {
  const config = await apiGetServerConfig();
  if (!config.enabled || !config.url) {
    return false;
  }
  const result = await apiTestServerConnection(config.url);
  const isOnline = result.success;
  await saveSyncState({ isOnline });
  return isOnline;
}

// ===== 统一存储接口（带 Hybrid 后缀） =====

// 获取链接列表
export async function getLinksHybrid(
  page: number = 1,
  pageSize: number = 50,
  options?: { 
    sortBy?: 'createdAt' | 'title' | 'domain';
    sortDesc?: boolean;
    domain?: string;
    search?: string;
  }
): Promise<{ links: LinkItem[]; total: number }> {
  const serverAvailable = await checkServerHealthHybrid();
  
  if (serverAvailable) {
    try {
      // 服务器可用，从服务器获取
      const result = await apiGetLinks(page, pageSize);
      return result;
    } catch (error) {
      console.warn('[HybridStorage] Server error, falling back to local:', error);
    }
  }
  
  // 服务器不可用，从本地获取
  // 本地只支持 createdAt 和 title 排序
  const localSortBy = options?.sortBy === 'domain' ? 'title' : (options?.sortBy || 'createdAt');
  return localGetLinks(page, pageSize, localSortBy, options?.sortDesc !== false);
}

// 添加链接
export async function addLinkHybrid(link: Omit<LinkItem, 'id' | 'createdAt'>): Promise<LinkItem> {
  const serverAvailable = await checkServerHealthHybrid();
  const config = await apiGetServerConfig();
  
  // 始终先保存到本地
  const localItem = await localAddLink(link);
  
  if (serverAvailable && config.enabled) {
    try {
      // 服务器可用，同步到服务器
      await apiAddLink(localItem);
    } catch (error) {
      console.warn('[HybridStorage] Failed to sync to server, will retry later:', error);
      // 添加到待同步队列
      await addPendingItem({
        id: localItem.id,
        type: 'add',
        data: localItem,
        timestamp: Date.now(),
      });
    }
  } else if (config.enabled) {
    // 服务器不可用但已配置，添加到待同步队列
    await addPendingItem({
      id: localItem.id,
      type: 'add',
      data: localItem,
      timestamp: Date.now(),
    });
  }
  
  return localItem;
}

// 删除链接
export async function deleteLinkHybrid(id: string): Promise<{ success: boolean; record?: DeleteRecord }> {
  const serverAvailable = await checkServerHealthHybrid();
  const config = await apiGetServerConfig();
  
  // 始终先操作本地
  const result = await localDeleteLink(id);
  
  if (!result.success) {
    return result;
  }
  
  if (serverAvailable && config.enabled) {
    try {
      // 服务器可用，同步删除
      await apiDeleteLink(id);
    } catch (error) {
      console.warn('[HybridStorage] Failed to sync delete to server:', error);
      await addPendingItem({
        id: `delete_${id}`,
        type: 'delete',
        data: { id },
        timestamp: Date.now(),
      });
    }
  } else if (config.enabled) {
    await addPendingItem({
      id: `delete_${id}`,
      type: 'delete',
      data: { id },
      timestamp: Date.now(),
    });
  }
  
  return result;
}

// 从回收站还原
export async function restoreFromTrashHybrid(recordId: string): Promise<{ success: boolean; link?: LinkItem }> {
  const serverAvailable = await checkServerHealthHybrid();
  const config = await apiGetServerConfig();
  
  // 先操作本地
  const result = await localRestoreFromTrash(recordId);
  
  if (!result.success) {
    return result;
  }
  
  if (serverAvailable && config.enabled) {
    try {
      await apiRestoreFromTrash(recordId);
    } catch (error) {
      console.warn('[HybridStorage] Failed to sync restore:', error);
      await addPendingItem({
        id: `restore_${recordId}`,
        type: 'restore',
        data: { recordId },
        timestamp: Date.now(),
      });
    }
  } else if (config.enabled) {
    await addPendingItem({
      id: `restore_${recordId}`,
      type: 'restore',
      data: { recordId },
      timestamp: Date.now(),
    });
  }
  
  return result;
}

// 永久删除
export async function permanentlyDeleteFromTrashHybrid(recordId: string): Promise<boolean> {
  const serverAvailable = await checkServerHealthHybrid();
  const config = await apiGetServerConfig();
  
  // 先操作本地
  const result = await localPermanentlyDeleteFromTrash(recordId);
  
  if (serverAvailable && config.enabled) {
    try {
      await apiPermanentlyDelete(recordId);
    } catch (error) {
      console.warn('[HybridStorage] Failed to sync permanent delete:', error);
      await addPendingItem({
        id: `permdelete_${recordId}`,
        type: 'permanent_delete',
        data: { recordId },
        timestamp: Date.now(),
      });
    }
  } else if (config.enabled) {
    await addPendingItem({
      id: `permdelete_${recordId}`,
      type: 'permanent_delete',
      data: { recordId },
      timestamp: Date.now(),
    });
  }
  
  return result;
}

// 获取回收站列表
export async function getTrashItemsHybrid(): Promise<DeleteRecord[]> {
  const serverAvailable = await checkServerHealthHybrid();
  
  if (serverAvailable) {
    try {
      return await apiGetTrash();
    } catch (error) {
      console.warn('[HybridStorage] Server error, falling back to local:', error);
    }
  }
  
  return localGetTrashItems();
}

// 获取统计信息
export async function getStatsHybrid(): Promise<{ linkCount: number; trashCount: number }> {
  const serverAvailable = await checkServerHealthHybrid();
  
  if (serverAvailable) {
    try {
      return await apiGetStats();
    } catch (error) {
      console.warn('[HybridStorage] Server error, falling back to local:', error);
    }
  }
  
  return {
    linkCount: await localGetLinkCount(),
    trashCount: (await localGetTrashItems()).length,
  };
}

// 检查链接是否已存在
export async function isLinkExistsHybrid(url: string): Promise<boolean> {
  const serverAvailable = await checkServerHealthHybrid();
  
  if (serverAvailable) {
    try {
      // 从服务器获取所有链接检查（简单实现）
      const { links } = await apiGetLinks(1, 1000);
      return links.some(link => link.url === url);
    } catch (error) {
      console.warn('[HybridStorage] Server error, falling back to local:', error);
    }
  }
  
  return localIsLinkExists(url);
}

// ===== 同步功能 =====

// 执行同步
export async function syncPendingItemsHybrid(): Promise<{ 
  success: boolean; 
  synced: number; 
  failed: number;
  errors: string[];
}> {
  const config = await apiGetServerConfig();
  if (!config.enabled || !config.url) {
    return { success: true, synced: 0, failed: 0, errors: [] };
  }
  
  const serverAvailable = await checkServerHealthHybrid();
  if (!serverAvailable) {
    return { success: false, synced: 0, failed: 0, errors: ['服务器不可用'] };
  }
  
  const pendingItems = await getPendingItems();
  if (pendingItems.length === 0) {
    return { success: true, synced: 0, failed: 0, errors: [] };
  }
  
  const errors: string[] = [];
  let synced = 0;
  let failed = 0;
  const syncedIds: string[] = [];
  
  // 先处理添加操作（批量）
  const addItems = pendingItems.filter(item => item.type === 'add');
  if (addItems.length > 0) {
    try {
      await apiBatchAddLinks(addItems.map(item => item.data));
      synced += addItems.length;
      syncedIds.push(...addItems.map(item => item.id));
    } catch (error) {
      errors.push(`批量添加失败: ${error instanceof Error ? error.message : '未知错误'}`);
      failed += addItems.length;
    }
  }
  
  // 处理其他操作（单个）
  const otherItems = pendingItems.filter(item => item.type !== 'add');
  for (const item of otherItems) {
    try {
      switch (item.type) {
        case 'delete':
          await apiDeleteLink(item.data.id);
          break;
        case 'restore':
          await apiRestoreFromTrash(item.data.recordId);
          break;
        case 'permanent_delete':
          await apiPermanentlyDelete(item.data.recordId);
          break;
      }
      synced++;
      syncedIds.push(item.id);
    } catch (error) {
      failed++;
      errors.push(`${item.type} 失败: ${error instanceof Error ? error.message : '未知错误'}`);
    }
  }
  
  // 移除已同步的项目
  if (syncedIds.length > 0) {
    await removePendingItems(syncedIds);
  }
  
  // 更新最后同步时间
  if (synced > 0) {
    await saveSyncState({ lastSyncTime: Date.now() });
  }
  
  return { success: failed === 0, synced, failed, errors };
}

// 获取同步状态
export async function getSyncStatusHybrid(): Promise<{
  isOnline: boolean;
  pendingCount: number;
  lastSyncTime: number;
}> {
  const state = await getSyncState();
  return {
    isOnline: state.isOnline,
    pendingCount: state.pendingCount,
    lastSyncTime: state.lastSyncTime,
  };
}
