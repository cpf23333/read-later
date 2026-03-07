// IndexedDB 存储模块 - 用于存储大量链接数据

const DB_NAME = 'UrlMemDB';
const DB_VERSION = 1;
const STORE_NAME = 'links';
const CONFIG_STORE = 'config';

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

// 删除链接
export async function deleteLink(id: string): Promise<void> {
  const database = await initDB();

  return new Promise((resolve, reject) => {
    const transaction = database.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.delete(id);

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
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
