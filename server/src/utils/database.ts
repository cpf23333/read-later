/**
 * 数据库模块
 */

import Database from 'better-sqlite3';
import path from 'path';
import type { Link, TrashItem } from '../types/index.ts';

let db: Database.Database | null = null;

/**
 * 初始化数据库
 */
export function initDatabase(dataDir: string): Database.Database {
  const dbPath = path.join(dataDir, 'readlater.db');
  db = new Database(dbPath);

  // 创建表
  db.exec(`
    CREATE TABLE IF NOT EXISTS links (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      title TEXT,
      nearby_image TEXT,
      screenshot TEXT,
      source_page TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER,
      custom_data TEXT
    );

    CREATE TABLE IF NOT EXISTS trash (
      id TEXT PRIMARY KEY,
      link_id TEXT NOT NULL,
      url TEXT NOT NULL,
      title TEXT,
      nearby_image TEXT,
      screenshot TEXT,
      source_page TEXT,
      created_at INTEGER NOT NULL,
      deleted_at INTEGER NOT NULL,
      custom_data TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_links_created ON links(created_at);
    CREATE INDEX IF NOT EXISTS idx_trash_deleted ON trash(deleted_at);
  `);

  return db;
}

/**
 * 获取数据库实例
 */
export function getDatabase(): Database.Database {
  if (!db) {
    throw new Error('Database not initialized');
  }
  return db;
}

/**
 * 关闭数据库
 */
export function closeDatabase(): void {
  if (db) {
    db.close();
    db = null;
  }
}

// ===== 链接操作 =====

/**
 * 获取所有链接（支持分页和搜索）
 */
export function getLinks(
  page: number,
  pageSize: number,
  sortBy: string,
  sortOrder: 'asc' | 'desc',
  search?: string,
  domain?: string
): { links: Link[]; total: number } {
  const database = getDatabase();
  
  let sql = 'SELECT * FROM links';
  let countSql = 'SELECT COUNT(*) as count FROM links';
  const params: (string | number)[] = [];
  const conditions: string[] = [];

  // 搜索条件
  if (search) {
    conditions.push('(url LIKE ? OR title LIKE ? OR source_page LIKE ?)');
    const searchParam = `%${search}%`;
    params.push(searchParam, searchParam, searchParam);
  }

  // 域名过滤
  if (domain) {
    conditions.push('source_page LIKE ?');
    params.push(`%${domain}%`);
  }

  // 添加 WHERE 子句
  if (conditions.length > 0) {
    const whereClause = ' WHERE ' + conditions.join(' AND ');
    sql += whereClause;
    countSql += whereClause;
  }

  // 排序和分页
  sql += ` ORDER BY ${sortBy} ${sortOrder === 'asc' ? 'ASC' : 'DESC'}`;
  const offset = (page - 1) * pageSize;
  sql += ' LIMIT ? OFFSET ?';
  params.push(pageSize, offset);

  const links = database.prepare(sql).all(...params) as Link[];
  
  const countParams = conditions.length > 0 ? params.slice(0, -2) : [];
  const total = (database.prepare(countSql).get(...countParams) as { count: number }).count;

  return { links, total };
}

/**
 * 搜索链接
 */
export function searchLinks(query: string): Link[] {
  const database = getDatabase();
  const searchParam = `%${query}%`;
  
  return database.prepare(
    `SELECT * FROM links 
     WHERE url LIKE ? OR title LIKE ? OR source_page LIKE ?
     ORDER BY created_at DESC`
  ).all(searchParam, searchParam, searchParam) as Link[];
}

/**
 * 根据 ID 获取链接
 */
export function getLinkById(id: string): Link | undefined {
  const database = getDatabase();
  return database.prepare('SELECT * FROM links WHERE id = ?').get(id) as Link | undefined;
}

/**
 * 添加链接
 */
export function addLink(link: Omit<Link, 'updated_at'>): void {
  const database = getDatabase();
  const now = Date.now();
  
  database.prepare(
    `INSERT INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    link.id,
    link.url,
    link.title || '',
    link.nearby_image,
    link.screenshot,
    link.source_page || '',
    link.created_at,
    now,
    link.custom_data
  );
}

/**
 * 删除链接
 */
export function deleteLink(id: string): void {
  const database = getDatabase();
  database.prepare('DELETE FROM links WHERE id = ?').run(id);
}

// ===== 回收站操作 =====

/**
 * 添加项目到回收站
 */
export function addToTrash(item: Omit<TrashItem, 'id'>, trashId: string): void {
  const database = getDatabase();
  
  database.prepare(
    `INSERT INTO trash (id, link_id, url, title, nearby_image, screenshot, source_page, created_at, deleted_at, custom_data)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    trashId,
    item.link_id,
    item.url,
    item.title,
    item.nearby_image,
    item.screenshot,
    item.source_page,
    item.created_at,
    item.deleted_at,
    item.custom_data
  );
}

/**
 * 获取回收站所有项目
 */
export function getTrashItems(): TrashItem[] {
  const database = getDatabase();
  return database.prepare('SELECT * FROM trash ORDER BY deleted_at DESC').all() as TrashItem[];
}

/**
 * 根据 ID 获取回收站项目
 */
export function getTrashItemById(id: string): TrashItem | undefined {
  const database = getDatabase();
  return database.prepare('SELECT * FROM trash WHERE id = ?').get(id) as TrashItem | undefined;
}

/**
 * 从回收站删除
 */
export function deleteFromTrash(id: string): void {
  const database = getDatabase();
  database.prepare('DELETE FROM trash WHERE id = ?').run(id);
}

// ===== 统计操作 =====

/**
 * 获取统计信息
 */
export function getStats(): { linkCount: number; trashCount: number } {
  const database = getDatabase();
  
  const linkCount = (database.prepare('SELECT COUNT(*) as count FROM links').get() as { count: number }).count;
  const trashCount = (database.prepare('SELECT COUNT(*) as count FROM trash').get() as { count: number }).count;
  
  return { linkCount, trashCount };
}

/**
 * 获取域名统计
 */
export function getDomainStats(): Array<{ domain: string; count: number }> {
  const database = getDatabase();
  const links = database.prepare('SELECT source_page FROM links').all() as Array<{ source_page: string }>;
  
  const domainCounts = new Map<string, number>();
  
  for (const link of links) {
    try {
      const domain = new URL(link.source_page).hostname;
      if (domain) {
        domainCounts.set(domain, (domainCounts.get(domain) || 0) + 1);
      }
    } catch {
      // 忽略无效 URL
    }
  }
  
  return Array.from(domainCounts.entries())
    .map(([domain, count]) => ({ domain, count }))
    .sort((a, b) => b.count - a.count);
}

/**
 * 导出所有链接
 */
export function exportLinks(): Link[] {
  const database = getDatabase();
  return database.prepare('SELECT * FROM links').all() as Link[];
}
