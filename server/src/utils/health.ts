/**
 * 健康检查工具
 */

import fs from 'fs';
import path from 'path';
import { getDatabase, getStats } from './database.ts';

export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  version: string;
  timestamp: string;
  uptime: number;
  database: {
    connected: boolean;
    linkCount: number;
    trashCount: number;
    error?: string;
  };
  disk: {
    dataDir: string;
    free: number;
    total: number;
    usagePercent: number;
  };
  memory: {
    used: number;
    total: number;
    usagePercent: number;
  };
}

/**
 * 获取包版本号
 */
function getVersion(): string {
  try {
    const pkgPath = path.resolve(process.cwd(), 'package.json');
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8'));
    return pkg.version || 'unknown';
  } catch {
    return 'unknown';
  }
}

/**
 * 获取目录磁盘空间信息
 */
function getDiskInfo(dir: string): { free: number; total: number; usagePercent: number } {
  try {
    const stats = fs.statfsSync(dir);
    const total = stats.blocks * stats.bsize;
    const free = stats.bfree * stats.bsize;
    const used = total - free;
    const usagePercent = total > 0 ? Math.round((used / total) * 100) : 0;
    return { free, total, usagePercent };
  } catch {
    return { free: 0, total: 0, usagePercent: 0 };
  }
}

/**
 * 获取内存使用情况
 */
function getMemoryInfo(): { used: number; total: number; usagePercent: number } {
  const total = process.memoryUsage().heapTotal;
  const used = process.memoryUsage().heapUsed;
  const usagePercent = total > 0 ? Math.round((used / total) * 100) : 0;
  return { used, total, usagePercent };
}

/**
 * 执行健康检查
 */
export function checkHealth(dataDir: string): HealthStatus {
  const disk = getDiskInfo(dataDir);
  const memory = getMemoryInfo();

  let databaseConnected = false;
  let linkCount = 0;
  let trashCount = 0;
  let dbError: string | undefined;

  try {
    const db = getDatabase();
    db.prepare('SELECT 1').run();
    databaseConnected = true;
    const stats = getStats();
    linkCount = stats.linkCount;
    trashCount = stats.trashCount;
  } catch (error) {
    databaseConnected = false;
    dbError = error instanceof Error ? error.message : 'Database check failed';
  }

  // 状态判断：数据库不可用 = unhealthy，磁盘或内存使用率过高 = degraded
  let status: HealthStatus['status'] = 'healthy';
  if (!databaseConnected || disk.usagePercent >= 95 || memory.usagePercent >= 95) {
    status = 'unhealthy';
  } else if (disk.usagePercent >= 85 || memory.usagePercent >= 85) {
    status = 'degraded';
  }

  return {
    status,
    version: getVersion(),
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    database: {
      connected: databaseConnected,
      linkCount,
      trashCount,
      error: dbError,
    },
    disk: {
      dataDir,
      free: disk.free,
      total: disk.total,
      usagePercent: disk.usagePercent,
    },
    memory: {
      used: memory.used,
      total: memory.total,
      usagePercent: memory.usagePercent,
    },
  };
}
