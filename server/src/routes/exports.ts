/**
 * 导出任务路由
 */

import { Hono } from 'hono';
import fs from 'fs';
import path from 'path';
import {
  createExportTask,
  completeExportTask,
  failExportTask,
  getExportTasks,
  getExportTaskById,
  deleteExportTask,
} from '../utils/database.ts';
import { createBackupArchive } from '../utils/archive.ts';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import type { ApiResponse, ExportTask } from '../types/index.ts';

const app = new Hono();

const DATA_DIR = process.env.DATA_DIR || './data';
const EXPORTS_DIR = path.join(DATA_DIR, 'exports');

// 确保导出目录存在
if (!fs.existsSync(EXPORTS_DIR)) {
  fs.mkdirSync(EXPORTS_DIR, { recursive: true });
}

/**
 * 创建导出任务
 * POST /api/exports
 */
app.post('/', apiRateLimit, async (c) => {
  const taskId = `export_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  const filename = `backup_${taskId}.zip`;
  const filePath = path.join(EXPORTS_DIR, filename);

  // 记录任务到数据库
  createExportTask(taskId);

  // 异步执行打包（不阻塞响应）
  (async () => {
    try {
      const dbPath = path.join(DATA_DIR, 'readlater.db');
      const imagesDir = path.join(DATA_DIR, 'images');

      await createBackupArchive(dbPath, imagesDir, filePath);

      const stats = fs.statSync(filePath);
      completeExportTask(taskId, filename, filePath, stats.size);
    } catch (error) {
      console.error('[exports] Task failed:', taskId, error);
      failExportTask(taskId, (error as Error).message);
    }
  })();

  return c.json<ApiResponse<{ taskId: string; status: string }>>({
    success: true,
    data: { taskId, status: 'running' },
  });
});

/**
 * 获取所有导出任务
 * GET /api/exports
 */
app.get('/', async (c) => {
  const tasks = getExportTasks();
  return c.json<ApiResponse<ExportTask[]>>({ success: true, data: tasks });
});

/**
 * 下载导出文件
 * GET /api/exports/:id/download
 */
app.get('/:id/download', async (c) => {
  const id = c.req.param('id');
  const task = getExportTaskById(id);

  if (!task || task.status !== 'completed') {
    return c.json<ApiResponse>({ success: false, error: '导出任务不存在或尚未完成' }, 404);
  }

  if (!task.file_path || !fs.existsSync(task.file_path)) {
    return c.json<ApiResponse>({ success: false, error: '文件不存在' }, 404);
  }

  const file = fs.readFileSync(task.file_path);
  return new Response(file, {
    headers: {
      'Content-Type': 'application/zip',
      'Content-Disposition': `attachment; filename="${task.filename}"`,
    },
  });
});

/**
 * 删除导出任务及文件
 * DELETE /api/exports/:id
 */
app.delete('/:id', apiRateLimit, async (c) => {
  const id = c.req.param('id');
  const task = getExportTaskById(id);

  if (!task) {
    return c.json<ApiResponse>({ success: false, error: '导出任务不存在' }, 404);
  }

  // 删除物理文件
  if (task.file_path && fs.existsSync(task.file_path)) {
    fs.unlinkSync(task.file_path);
  }

  // 删除数据库记录
  deleteExportTask(id);

  return c.json<ApiResponse>({ success: true });
});

export default app;
