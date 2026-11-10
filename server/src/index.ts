/**
 * ReadLater Server - Hono + TypeScript
 *
 * 一个轻量级的链接收藏管理服务
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { serveStatic } from '@hono/node-server/serve-static';
import { serve } from '@hono/node-server';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

// 加载环境变量
dotenv.config();

// 导入模块
import { initDatabase, closeDatabase } from './utils/database.ts';
import { setImagesDir } from './utils/image.ts';
import { setApiKey, getApiKeyCount } from './middleware/auth.ts';
import { authMiddleware } from './middleware/auth.ts';
import { startBackupSchedule, stopBackupSchedule } from './utils/backup.ts';
import { logger } from './utils/logger.ts';
import { errorHandler } from './middleware/errorHandler.ts';
import { generalRateLimit } from './middleware/ratelimit.ts';
import { isAllowedExtension } from './utils/security.ts';

// 导入路由
import linksRoute from './routes/links.ts';
import trashRoute from './routes/trash.ts';
import domainsRoute from './routes/domains.ts';
import settingsRoute from './routes/settings.ts';
import statsRoute from './routes/stats.ts';
import uploadRoute from './routes/upload.ts';
import healthRoute from './routes/health.ts';
import exportsRoute from './routes/exports.ts';
import sitesRoute from './routes/sites.ts';

// 配置
const PORT = parseInt(process.env.PORT || '3000', 10);
const DATA_DIR = process.env.DATA_DIR || './data';
const API_KEY = process.env.API_KEY;
const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',')
  : ['*'];

// 检查 API_KEY 是否配置
if (!API_KEY) {
  logger.error('启动失败：缺少 API_KEY 环境变量', {
    hint: '请设置 API_KEY 环境变量，例如：API_KEY=your-secret-api-key',
    generate: 'openssl rand -base64 32',
  });
  process.exit(1);
}

// 设置 API Key
setApiKey(API_KEY);

// 确保数据目录存在
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 图片存储目录
const IMAGES_DIR = path.join(DATA_DIR, 'images');
const THUMBS_DIR = path.join(DATA_DIR, 'images', 'thumbs');
const DELETED_IMAGES_DIR = path.join(DATA_DIR, 'images', 'deleted');

if (!fs.existsSync(IMAGES_DIR)) {
  fs.mkdirSync(IMAGES_DIR, { recursive: true });
}
if (!fs.existsSync(THUMBS_DIR)) {
  fs.mkdirSync(THUMBS_DIR, { recursive: true });
}
if (!fs.existsSync(DELETED_IMAGES_DIR)) {
  fs.mkdirSync(DELETED_IMAGES_DIR, { recursive: true });
}

// 设置图片目录
setImagesDir(IMAGES_DIR);

// 初始化数据库
initDatabase(DATA_DIR);

// 启动数据库自动备份
const backupIntervalHours = parseInt(process.env.BACKUP_INTERVAL_HOURS || '24', 10);
const backupKeepCount = parseInt(process.env.BACKUP_KEEP_COUNT || '7', 10);
startBackupSchedule({
  dataDir: DATA_DIR,
  intervalHours: Number.isNaN(backupIntervalHours) ? 24 : backupIntervalHours,
  keepCount: Number.isNaN(backupKeepCount) ? 7 : backupKeepCount,
});

// 创建 Hono 应用
const app = new Hono();

// 全局错误处理
app.use(errorHandler);

// 全局限流
app.use(generalRateLimit);

// CORS 配置
app.use(
  cors({
    origin: (origin) => {
      // 允许无来源（如 Postman）或配置的允许列表
      if (!origin || ALLOWED_ORIGINS.includes('*') || ALLOWED_ORIGINS.includes(origin)) {
        return origin || '*';
      }
      return '*';
    },
    allowMethods: ['GET', 'POST', 'DELETE'],
    allowHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
  })
);

// 静态文件服务 - 只允许访问图片文件
app.use('/images/*', async (c, next) => {
  const pathname = new URL(c.req.url).pathname;

  // 阻止访问隐藏文件或路径遍历
  if (pathname.includes('..') || pathname.includes('/.')) {
    return c.json({ success: false, error: 'Forbidden' }, 403);
  }

  // 只允许图片文件扩展名
  const ext = path.extname(pathname).toLowerCase();
  if (!isAllowedExtension(ext)) {
    return c.json({ success: false, error: 'Invalid file type' }, 403);
  }

  await next();
  return c.notFound();
});

// 普通图片目录
app.use('/images/*', serveStatic({ root: DATA_DIR }));

// 回收站图片目录（需要检查鉴权）
app.use('/images/deleted/*', authMiddleware);
app.use('/images/deleted/*', serveStatic({ root: DATA_DIR }));

// API 路由
// 健康检查（公开）
app.route('/api/health', healthRoute);

// 需要鉴权的 API
app.use('/api/*', authMiddleware);

// 各模块路由
app.route('/api/links', linksRoute);
app.route('/api/trash', trashRoute);
app.route('/api/domains', domainsRoute);
app.route('/api/stats', statsRoute);
app.route('/api/sites', sitesRoute);
app.route('/api/settings', settingsRoute);
app.route('/api/upload', uploadRoute);

// 搜索路由（挂载在 /api/search）
app.route('/api/search', linksRoute);

// 导出/导入路由
app.route('/api/export', linksRoute);
app.route('/api/import', linksRoute);
app.route('/api/exports', exportsRoute);

// 启动服务器
serve(
  {
    fetch: app.fetch,
    port: PORT,
    hostname: '0.0.0.0',
  },
  (info) => {
    logger.info('ReadLater 服务器已启动', {
      address: `http://0.0.0.0:${info.port}`,
      dataDir: DATA_DIR,
      authEnabled: true,
      apiKeyCount: getApiKeyCount(),
    });
  }
);

// 优雅关闭
process.on('SIGINT', () => {
  logger.info('正在关闭服务器...');
  stopBackupSchedule();
  closeDatabase();
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('正在关闭服务器...');
  stopBackupSchedule();
  closeDatabase();
  process.exit(0);
});
