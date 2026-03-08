// IndexedDB 存储模块 - 用于存储大量链接数据

const DB_NAME = 'ReadLaterDB';
const DB_VERSION = 2; // 升级数据库版本
const STORE_NAME = 'links';
const CONFIG_STORE = 'config';
const SYNC_META_STORE = 'sync_meta'; // 同步元数据存储

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

let db: IDBDatabase | null = null;

// 初始化数据库
async function initDB(): Promise<IDBDatabase> {
  if (db) return db;

  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      db = request.result;
      resolve(db);
    };

    request.onupgradeneeded = (event) => {
      const database = (event.target as IDBOpenDBRequest).result;
      const oldVersion = event.oldVersion;
      
      // 链接存储
      if (!database.objectStoreNames.contains(STORE_NAME)) {
        const linkStore = database.createObjectStore(STORE_NAME, { keyPath: 'id' });
        linkStore.createIndex('url', 'url', { unique: false });
        linkStore.createIndex('createdAt', 'createdAt', { unique: false });
        linkStore.createIndex('sourcePage', 'sourcePage', { unique: false });
      }
      
      // 配置存储
      if (!database.objectStoreNames.contains(CONFIG_STORE)) {
        database.createObjectStore(CONFIG_STORE, { keyPath: 'id' });
      }
      
      // 同步元数据存储 (v2 新增)
      if (!database.objectStoreNames.contains(SYNC_META_STORE)) {
        const syncStore = database.createObjectStore(SYNC_META_STORE, { keyPath: 'id' });
        syncStore.createIndex('deletedAt', 'deletedAt', { unique: false });
      }
    };
  });
}

// 添加链接
export async function addLink(link: Omit<LinkItem, 'id' | 'createdAt'>): Promise<LinkItem> {
  const database = await initDB();
  
  const item: LinkItem = {
    ...link,
    id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    createdAt: Date.now(),
  };

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.add(item);

    request.onsuccess = () => resolve(item);
    request.onerror = () => reject(request.error);
  });
}

// 获取所有链接（支持分页）
export async function getLinks(
  page: number = 1,
  pageSize: number = 50,
  sortBy: 'createdAt' | 'title' = 'createdAt',
  sortDesc: boolean = true
): Promise<{ links: LinkItem[]; total: number }> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    
    const links: LinkItem[] = [];
    const request = store.openCursor(null, sortDesc ? 'prev' : 'next');

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        links.push(cursor.value);
        cursor.continue();
      } else {
        // 简单的内存分页
        const total = links.length;
        const start = (page - 1) * pageSize;
        const paginatedLinks = links.slice(start, start + pageSize);
        resolve({ links: paginatedLinks, total });
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 根据ID获取链接
export async function getLinkById(id: string): Promise<LinkItem | null> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.get(id);

    request.onsuccess = () => resolve(request.result || null);
    request.onerror = () => reject(request.error);
  });
}

// 删除链接（移入回收站）
export async function deleteLink(id: string): Promise<{ 
  success: boolean; 
  record?: DeleteRecord;
}> {
  const database = await initDB();

  // 先获取链接信息
  const link = await getLinkById(id);
  if (!link) {
    return { success: false };
  }

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME, SYNC_META_STORE], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const deleteRequest = store.delete(id);

    deleteRequest.onsuccess = () => {
      // 创建完整的删除记录（用于回收站和同步）
      const record: DeleteRecord = {
        id: `delete_${link.url}`,
        linkId: link.id,
        url: link.url,
        title: link.title,
        sourcePage: link.sourcePage,
        createdAt: link.createdAt,
        deletedAt: Date.now(),
        normalizedUrl: normalizeUrl(link.url),
        nearbyImage: link.nearbyImage,
        screenshot: link.screenshot,
        customData: link.customData,
      };
      
      const syncStore = transaction.objectStore(SYNC_META_STORE);
      syncStore.put(record);
      
      resolve({ 
        success: true, 
        record,
      });
    };
    deleteRequest.onerror = () => reject(deleteRequest.error);
  });
}

// 批量删除链接
export async function deleteLinks(ids: string[]): Promise<void> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);

    let completed = 0;
    ids.forEach((id) => {
      const request = store.delete(id);
      request.onsuccess = () => {
        completed++;
        if (completed === ids.length) resolve();
      };
      request.onerror = () => reject(request.error);
    });
  });
}

// 搜索链接
export async function searchLinks(query: string): Promise<LinkItem[]> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    const results: LinkItem[] = [];
    const lowerQuery = query.toLowerCase();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const item = cursor.value as LinkItem;
        if (
          item.url.toLowerCase().includes(lowerQuery) ||
          item.title.toLowerCase().includes(lowerQuery) ||
          item.sourcePage.toLowerCase().includes(lowerQuery)
        ) {
          results.push(item);
        }
        cursor.continue();
      } else {
        resolve(results);
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 导出所有链接为JSON
export async function exportLinks(): Promise<string> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    const links: LinkItem[] = [];

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        links.push(cursor.value);
        cursor.continue();
      } else {
        resolve(JSON.stringify(links, null, 2));
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 导入链接（支持合并或覆盖）
export interface ImportResult {
  imported: number;
  skipped: number;
  total: number;
}

export async function importLinks(
  jsonString: string, 
  mode: 'merge' | 'replace' = 'merge'
): Promise<ImportResult> {
  let data: LinkItem[];
  try {
    data = JSON.parse(jsonString);
    if (!Array.isArray(data)) {
      throw new Error('Invalid format: expected an array');
    }
  } catch (error) {
    throw new Error('无效的JSON文件');
  }

  const database = await initDB();
  
  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);

    let imported = 0;
    let skipped = 0;

    // 如果是替换模式，先清空所有数据
    const clearRequest = mode === 'replace' ? store.clear() : null;

    const processItems = () => {
      const existingUrls = new Set<string>();
      
      // 先获取所有现有URL
      const cursorRequest = store.openCursor();
      cursorRequest.onsuccess = (event) => {
        const cursor = (event.target as IDBRequest).result;
        if (cursor) {
          const item = cursor.value as LinkItem;
          existingUrls.add(normalizeUrl(item.url));
          cursor.continue();
        } else {
          // 开始导入
          importNextItem(0);
        }
      };
      cursorRequest.onerror = () => reject(cursorRequest.error);
    };

    const importNextItem = (index: number) => {
      if (index >= data.length) {
        resolve({ imported, skipped, total: data.length });
        return;
      }

      const item = data[index];
      
      // 验证数据格式
      if (!item.url || !item.title) {
        skipped++;
        importNextItem(index + 1);
        return;
      }

      // 检查是否已存在
      const normalizedUrl = normalizeUrl(item.url);
      const checkRequest = store.openCursor();
      let exists = false;

      checkRequest.onsuccess = (event) => {
        const cursor = (event.target as IDBRequest).result;
        if (cursor && !exists) {
          const existing = cursor.value as LinkItem;
          if (normalizeUrl(existing.url) === normalizedUrl) {
            exists = true;
          } else {
            cursor.continue();
          }
        } else {
          if (exists) {
            skipped++;
            importNextItem(index + 1);
          } else {
            // 添加新链接（重新生成ID和时间戳）
            const newItem: LinkItem = {
              ...item,
              id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}_${index}`,
              createdAt: item.createdAt || Date.now(),
            };

            const addRequest = store.add(newItem);
            addRequest.onsuccess = () => {
              imported++;
              importNextItem(index + 1);
            };
            addRequest.onerror = () => {
              skipped++;
              importNextItem(index + 1);
            };
          }
        }
      };
      checkRequest.onerror = () => reject(checkRequest.error);
    };

    if (mode === 'replace') {
      clearRequest!.onsuccess = processItems;
      clearRequest!.onerror = () => reject(clearRequest!.error);
    } else {
      processItems();
    }
  });
}

// 保存自定义JS配置
export async function saveCustomJsConfig(config: CustomJsConfig): Promise<void> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([CONFIG_STORE], 'readwrite');
    const store = transaction.objectStore(CONFIG_STORE);
    const request = store.put(config);

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

// 获取所有自定义JS配置
export async function getCustomJsConfigs(): Promise<CustomJsConfig[]> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([CONFIG_STORE], 'readonly');
    const store = transaction.objectStore(CONFIG_STORE);
    const request = store.openCursor();

    const configs: CustomJsConfig[] = [];

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        configs.push(cursor.value);
        cursor.continue();
      } else {
        resolve(configs);
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 获取启用的自定义JS配置
export async function getEnabledCustomJsConfig(): Promise<CustomJsConfig | null> {
  const configs = await getCustomJsConfigs();
  return configs.find(c => c.enabled) || null;
}

// 删除自定义JS配置
export async function deleteCustomJsConfig(id: string): Promise<void> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([CONFIG_STORE], 'readwrite');
    const store = transaction.objectStore(CONFIG_STORE);
    const request = store.delete(id);

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

// 获取删除记录（用于同步和回收站）
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

export async function getDeleteRecords(since?: number): Promise<DeleteRecord[]> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([SYNC_META_STORE], 'readonly');
    const store = transaction.objectStore(SYNC_META_STORE);
    const request = store.openCursor();

    const records: DeleteRecord[] = [];

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const record = cursor.value as DeleteRecord;
        if (!since || record.deletedAt > since) {
          records.push(record);
        }
        cursor.continue();
      } else {
        resolve(records);
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 获取回收站列表
export async function getTrashItems(): Promise<DeleteRecord[]> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([SYNC_META_STORE], 'readonly');
    const store = transaction.objectStore(SYNC_META_STORE);
    const request = store.openCursor();

    const records: DeleteRecord[] = [];

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const record = cursor.value as DeleteRecord;
        // 只返回删除记录（id 以 delete_ 开头）
        if (record.id.startsWith('delete_')) {
          records.push(record);
        }
        cursor.continue();
      } else {
        // 按删除时间倒序排列
        resolve(records.sort((a, b) => b.deletedAt - a.deletedAt));
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 从回收站还原链接
export async function restoreFromTrash(recordId: string): Promise<{ success: boolean; link?: LinkItem }> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME, SYNC_META_STORE], 'readwrite');
    const syncStore = transaction.objectStore(SYNC_META_STORE);
    
    // 获取删除记录
    const getRequest = syncStore.get(recordId);
    
    getRequest.onsuccess = () => {
      const record = getRequest.result as DeleteRecord | undefined;
      if (!record) {
        resolve({ success: false });
        return;
      }
      
      // 创建新链接（使用原始ID，但更新时间戳）
      const restoredLink: LinkItem = {
        id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        url: record.url,
        title: record.title,
        nearbyImage: record.nearbyImage,
        screenshot: record.screenshot,
        sourcePage: record.sourcePage,
        createdAt: Date.now(), // 重新创建时间
        customData: record.customData,
      };
      
      // 保存到链接表
      const linkStore = transaction.objectStore(STORE_NAME);
      linkStore.add(restoredLink);
      
      // 从回收站删除
      syncStore.delete(recordId);
      
      resolve({ success: true, link: restoredLink });
    };
    
    getRequest.onerror = () => reject(getRequest.error);
  });
}

// 永久删除回收站项目
export async function permanentlyDeleteFromTrash(recordId: string): Promise<boolean> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([SYNC_META_STORE], 'readwrite');
    const store = transaction.objectStore(SYNC_META_STORE);
    const request = store.delete(recordId);

    request.onsuccess = () => resolve(true);
    request.onerror = () => reject(request.error);
  });
}

// 清空回收站
export async function clearTrash(): Promise<number> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([SYNC_META_STORE], 'readwrite');
    const store = transaction.objectStore(SYNC_META_STORE);
    const request = store.openCursor();

    let deletedCount = 0;

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const record = cursor.value as DeleteRecord;
        if (record.id.startsWith('delete_')) {
          store.delete(record.id);
          deletedCount++;
        }
        cursor.continue();
      } else {
        resolve(deletedCount);
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 清除旧的删除记录
export async function clearOldDeleteRecords(before: number): Promise<void> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([SYNC_META_STORE], 'readwrite');
    const store = transaction.objectStore(SYNC_META_STORE);
    const request = store.openCursor();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const record = cursor.value as DeleteRecord;
        if (record.deletedAt < before) {
          store.delete(record.id);
        }
        cursor.continue();
      } else {
        resolve();
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 根据URL检查是否被删除
export async function isUrlDeleted(url: string): Promise<boolean> {
  const database = await initDB();
  const normalizedUrl = normalizeUrl(url);

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([SYNC_META_STORE], 'readonly');
    const store = transaction.objectStore(SYNC_META_STORE);
    const request = store.openCursor();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const record = cursor.value as DeleteRecord;
        if (record.normalizedUrl === normalizedUrl) {
          resolve(true);
          return;
        }
        cursor.continue();
      } else {
        resolve(false);
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 获取链接总数
export async function getLinkCount(): Promise<number> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.count();

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

// 检查链接是否已存在（根据URL判断）
export async function isLinkExists(url: string): Promise<boolean> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const item = cursor.value as LinkItem;
        // 标准化URL后比较（忽略末尾斜杠、hash、部分参数等）
        if (normalizeUrl(item.url) === normalizeUrl(url)) {
          resolve(true);
          return;
        }
        cursor.continue();
      } else {
        resolve(false);
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 根据URL查找已存在的链接
export async function getLinkByUrl(url: string): Promise<LinkItem | null> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const item = cursor.value as LinkItem;
        if (normalizeUrl(item.url) === normalizeUrl(url)) {
          resolve(item);
          return;
        }
        cursor.continue();
      } else {
        resolve(null);
      }
    };

    request.onerror = () => reject(request.error);
  });
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

// 获取所有域名列表
export async function getAllDomains(): Promise<string[]> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    const domains = new Set<string>();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const item = cursor.value as LinkItem;
        try {
          const domain = new URL(item.url).hostname;
          if (domain) domains.add(domain);
        } catch {
          // 无效URL忽略
        }
        cursor.continue();
      } else {
        resolve(Array.from(domains).sort());
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 高级查询链接（支持排序、筛选、分页）
export interface LinkQueryOptions {
  page?: number;
  pageSize?: number;
  sortBy?: 'createdAt' | 'title' | 'domain';
  sortOrder?: 'asc' | 'desc';
  domainFilter?: string | null;
  dateFrom?: number | null;
  dateTo?: number | null;
}

export async function queryLinks(
  options: LinkQueryOptions = {}
): Promise<{ links: LinkItem[]; total: number }> {
  const {
    page = 1,
    pageSize = 50,
    sortBy = 'createdAt',
    sortOrder = 'desc',
    domainFilter = null,
    dateFrom = null,
    dateTo = null,
  } = options;

  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    let allLinks: LinkItem[] = [];

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const item = cursor.value as LinkItem;
        
        // 应用过滤器
        let match = true;
        
        // 域名过滤
        if (domainFilter) {
          try {
            const itemDomain = new URL(item.url).hostname;
            if (itemDomain !== domainFilter) match = false;
          } catch {
            match = false;
          }
        }
        
        // 日期范围过滤
        if (dateFrom && item.createdAt < dateFrom) match = false;
        if (dateTo && item.createdAt > dateTo) match = false;
        
        if (match) {
          allLinks.push(item);
        }
        
        cursor.continue();
      } else {
        // 排序
        allLinks.sort((a, b) => {
          let comparison = 0;
          
          switch (sortBy) {
            case 'createdAt':
              comparison = a.createdAt - b.createdAt;
              break;
            case 'title':
              comparison = (a.title || '').localeCompare(b.title || '');
              break;
            case 'domain':
              try {
                const domainA = new URL(a.url).hostname;
                const domainB = new URL(b.url).hostname;
                comparison = domainA.localeCompare(domainB);
              } catch {
                comparison = a.url.localeCompare(b.url);
              }
              break;
          }
          
          return sortOrder === 'desc' ? -comparison : comparison;
        });
        
        // 分页
        const total = allLinks.length;
        const start = (page - 1) * pageSize;
        const paginatedLinks = allLinks.slice(start, start + pageSize);
        
        resolve({ links: paginatedLinks, total });
      }
    };

    request.onerror = () => reject(request.error);
  });
}

// 按域名统计链接数量
export async function getDomainStats(): Promise<{ domain: string; count: number }[]> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.openCursor();

    const domainCounts = new Map<string, number>();

    request.onsuccess = (event) => {
      const cursor = (event.target as IDBRequest).result;
      if (cursor) {
        const item = cursor.value as LinkItem;
        try {
          const domain = new URL(item.url).hostname;
          if (domain) {
            domainCounts.set(domain, (domainCounts.get(domain) || 0) + 1);
          }
        } catch {
          // 无效URL忽略
        }
        cursor.continue();
      } else {
        const stats = Array.from(domainCounts.entries())
          .map(([domain, count]) => ({ domain, count }))
          .sort((a, b) => b.count - a.count);
        resolve(stats);
      }
    };

    request.onerror = () => reject(request.error);
  });
}
