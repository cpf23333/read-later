/**
 * 数据库自动备份
 */

import fs from 'fs';
import path from 'path';

interface BackupOptions {
  dataDir: string;
  intervalHours?: number;
  keepCount?: number;
}

let backupTimer: ReturnType<typeof setInterval> | null = null;

/**
 * 格式化日期为文件名
 */
function formatDateForFilename(date: Date): string {
  const pad = (n: number) => n.toString().padStart(2, '0');
  return (
    `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-` +
    `${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`
  );
}

/**
 * 清理旧备份，只保留最近 keepCount 个
 */
function cleanupOldBackups(backupDir: string, keepCount: number): void {
  try {
    const files = fs
      .readdirSync(backupDir)
      .filter((name) => name.startsWith('readlater-') && name.endsWith('.db'))
      .map((name) => ({
        name,
        path: path.join(backupDir, name),
        mtime: fs.statSync(path.join(backupDir, name)).mtime.getTime(),
      }))
      .sort((a, b) => b.mtime - a.mtime);

    const toDelete = files.slice(keepCount);
    for (const file of toDelete) {
      fs.unlinkSync(file.path);
      console.log(`[Backup] Cleaned up old backup: ${file.name}`);
    }
  } catch (error) {
    console.error('[Backup] Failed to cleanup old backups:', error);
  }
}

/**
 * 执行一次备份
 */
export function performBackup(options: BackupOptions): string | null {
  const { dataDir, keepCount = 7 } = options;
  const dbPath = path.join(dataDir, 'readlater.db');
  const backupDir = path.join(dataDir, 'backups');

  if (!fs.existsSync(dbPath)) {
    console.error('[Backup] Database file not found:', dbPath);
    return null;
  }

  if (!fs.existsSync(backupDir)) {
    fs.mkdirSync(backupDir, { recursive: true });
  }

  const timestamp = formatDateForFilename(new Date());
  const backupName = `readlater-${timestamp}.db`;
  const backupPath = path.join(backupDir, backupName);

  try {
    fs.copyFileSync(dbPath, backupPath);
    console.log(`[Backup] Created: ${backupPath}`);
    cleanupOldBackups(backupDir, keepCount);
    return backupPath;
  } catch (error) {
    console.error('[Backup] Failed:', error);
    return null;
  }
}

/**
 * 启动定时备份
 */
export function startBackupSchedule(options: BackupOptions): void {
  if (backupTimer) {
    clearInterval(backupTimer);
    backupTimer = null;
  }

  const intervalHours = options.intervalHours ?? 24;
  const intervalMs = intervalHours * 60 * 60 * 1000;

  if (intervalHours <= 0) {
    console.log('[Backup] Auto backup disabled');
    return;
  }

  // 启动时立即执行一次备份
  performBackup(options);

  backupTimer = setInterval(() => {
    performBackup(options);
  }, intervalMs);

  console.log(`[Backup] Scheduled every ${intervalHours} hour(s)`);
}

/**
 * 停止定时备份
 */
export function stopBackupSchedule(): void {
  if (backupTimer) {
    clearInterval(backupTimer);
    backupTimer = null;
    console.log('[Backup] Schedule stopped');
  }
}

/**
 * 获取备份列表
 */
export function listBackups(dataDir: string): Array<{ name: string; path: string; size: number; createdAt: number }> {
  const backupDir = path.join(dataDir, 'backups');
  if (!fs.existsSync(backupDir)) {
    return [];
  }

  try {
    return fs
      .readdirSync(backupDir)
      .filter((name) => name.startsWith('readlater-') && name.endsWith('.db'))
      .map((name) => {
        const filePath = path.join(backupDir, name);
        const stat = fs.statSync(filePath);
        return {
          name,
          path: filePath,
          size: stat.size,
          createdAt: stat.mtime.getTime(),
        };
      })
      .sort((a, b) => b.createdAt - a.createdAt);
  } catch (error) {
    console.error('[Backup] Failed to list backups:', error);
    return [];
  }
}
