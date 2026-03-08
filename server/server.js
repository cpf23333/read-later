/**
 * 稍后再看 - SQLite 后端服务
 * 
 * 启动: npm start
 * 默认端口: 3000
 */

const express = require('express');
const Database = require('better-sqlite3');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;
const DATA_DIR = process.env.DATA_DIR || './data';

// 确保数据目录存在
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 图片存储目录
const IMAGES_DIR = path.join(DATA_DIR, 'images');
const DELETED_IMAGES_DIR = path.join(DATA_DIR, 'images', 'deleted');

if (!fs.existsSync(IMAGES_DIR)) {
  fs.mkdirSync(IMAGES_DIR, { recursive: true });
}
if (!fs.existsSync(DELETED_IMAGES_DIR)) {
  fs.mkdirSync(DELETED_IMAGES_DIR, { recursive: true });
}

// 初始化 SQLite 数据库
const db = new Database(path.join(DATA_DIR, 'readlater.db'));

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

// 中间件
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use('/images', express.static(IMAGES_DIR));

// ===== 链接 API =====

// 获取所有链接
app.get('/api/links', (req, res) => {
  try {
    const { page = 1, pageSize = 50, sortBy = 'created_at', sortOrder = 'desc' } = req.query;
    
    let sql = 'SELECT * FROM links';
    sql += ` ORDER BY ${sortBy} ${sortOrder === 'asc' ? 'ASC' : 'DESC'}`;
    
    const offset = (page - 1) * pageSize;
    sql += ' LIMIT ? OFFSET ?';
    
    const links = db.prepare(sql).all(parseInt(pageSize), parseInt(offset));
    const total = db.prepare('SELECT COUNT(*) as count FROM links').get().count;
    
    res.json({ success: true, data: links, total });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 添加链接
app.post('/api/links', (req, res) => {
  try {
    const { id, url, title, nearby_image, screenshot, source_page, created_at, custom_data } = req.body;
    
    const now = Date.now();
    db.prepare(`
      INSERT INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id || `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      url,
      title || '',
      nearby_image || null,
      screenshot || null,
      source_page || '',
      created_at || now,
      now,
      JSON.stringify(custom_data || {})
    );
    
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 批量添加链接
app.post('/api/links/batch', (req, res) => {
  try {
    const { links } = req.body;
    const insert = db.prepare(`
      INSERT OR REPLACE INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    
    const insertMany = db.transaction((items) => {
      for (const item of items) {
        insert.run(
          item.id,
          item.url,
          item.title || '',
          item.nearby_image || item.nearbyImage || null,
          item.screenshot || null,
          item.source_page || item.sourcePage || '',
          item.created_at || item.createdAt || Date.now(),
          Date.now(),
          JSON.stringify(item.custom_data || item.customData || {})
        );
      }
    });
    
    insertMany(links);
    res.json({ success: true, count: links.length });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 删除链接（移入回收站）
app.delete('/api/links/:id', (req, res) => {
  try {
    const link = db.prepare('SELECT * FROM links WHERE id = ?').get(req.params.id);
    if (!link) {
      return res.status(404).json({ success: false, error: 'Link not found' });
    }
    
    // 移入回收站
    const trashId = `delete_${link.id}_${Date.now()}`;
    db.prepare(`
      INSERT INTO trash (id, link_id, url, title, nearby_image, screenshot, source_page, created_at, deleted_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      trashId, link.id, link.url, link.title, link.nearby_image, link.screenshot,
      link.source_page, link.created_at, Date.now(), link.custom_data
    );
    
    // 从主表删除
    db.prepare('DELETE FROM links WHERE id = ?').run(req.params.id);
    
    // 移动图片到 deleted 文件夹
    const timestamp = new Date().toISOString().slice(0, 10);
    [link.nearby_image, link.screenshot].forEach(imgPath => {
      if (imgPath) {
        const filename = path.basename(imgPath);
        const oldPath = path.join(IMAGES_DIR, filename);
        const newPath = path.join(DELETED_IMAGES_DIR, `${timestamp}_${filename}`);
        if (fs.existsSync(oldPath)) {
          fs.renameSync(oldPath, newPath);
        }
      }
    });
    
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 回收站 API =====

app.get('/api/trash', (req, res) => {
  try {
    const items = db.prepare('SELECT * FROM trash ORDER BY deleted_at DESC').all();
    res.json({ success: true, data: items });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/trash/:id/restore', (req, res) => {
  try {
    const item = db.prepare('SELECT * FROM trash WHERE id = ?').get(req.params.id);
    if (!item) return res.status(404).json({ success: false, error: 'Not found' });
    
    const newId = `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    db.prepare(`
      INSERT INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      newId, item.url, item.title, item.nearby_image, item.screenshot,
      item.source_page, Date.now(), Date.now(), item.custom_data
    );
    
    db.prepare('DELETE FROM trash WHERE id = ?').run(req.params.id);
    
    // 还原图片
    const files = fs.readdirSync(DELETED_IMAGES_DIR);
    [item.nearby_image, item.screenshot].forEach(imgPath => {
      if (imgPath) {
        const filename = path.basename(imgPath);
        const match = files.find(f => f.endsWith(filename));
        if (match) {
          fs.renameSync(
            path.join(DELETED_IMAGES_DIR, match),
            path.join(IMAGES_DIR, filename)
          );
        }
      }
    });
    
    res.json({ success: true, data: { newId } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/trash/:id', (req, res) => {
  try {
    const item = db.prepare('SELECT * FROM trash WHERE id = ?').get(req.params.id);
    if (item) {
      // 删除图片
      const files = fs.readdirSync(DELETED_IMAGES_DIR);
      [item.nearby_image, item.screenshot].forEach(imgPath => {
        if (imgPath) {
          const filename = path.basename(imgPath);
          const match = files.find(f => f.endsWith(filename));
          if (match) fs.unlinkSync(path.join(DELETED_IMAGES_DIR, match));
        }
      });
    }
    
    db.prepare('DELETE FROM trash WHERE id = ?').run(req.params.id);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 图片上传 API =====

app.post('/api/upload', (req, res) => {
  try {
    const { image, filename } = req.body;
    if (!image) return res.status(400).json({ success: false, error: 'No image' });
    
    const base64Data = image.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64Data, 'base64');
    
    const finalFilename = filename || `${Date.now()}_${Math.random().toString(36).substr(2, 9)}.png`;
    fs.writeFileSync(path.join(IMAGES_DIR, finalFilename), buffer);
    
    res.json({ success: true, data: { url: `/images/${finalFilename}` } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 统计 API =====

app.get('/api/stats', (req, res) => {
  try {
    const linkCount = db.prepare('SELECT COUNT(*) as count FROM links').get().count;
    const trashCount = db.prepare('SELECT COUNT(*) as count FROM trash').get().count;
    
    res.json({ success: true, data: { linkCount, trashCount } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 导出/导入 API =====

app.get('/api/export', (req, res) => {
  try {
    const links = db.prepare('SELECT * FROM links').all();
    res.json({ success: true, data: links });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/import', (req, res) => {
  try {
    const { links, mode = 'merge' } = req.body;
    
    if (mode === 'replace') {
      db.prepare('DELETE FROM links').run();
    }
    
    const stmt = db.prepare(`
      INSERT OR IGNORE INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    
    let imported = 0;
    const insertMany = db.transaction((items) => {
      for (const item of items) {
        try {
          stmt.run(
            item.id || `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            item.url, item.title || '', item.nearby_image || item.nearbyImage || null,
            item.screenshot || null, item.source_page || item.sourcePage || '',
            item.created_at || item.createdAt || Date.now(), Date.now(),
            JSON.stringify(item.custom_data || item.customData || {})
          );
          imported++;
        } catch (e) {}
      }
    });
    
    insertMany(links);
    res.json({ success: true, data: { imported, total: links.length } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 健康检查
app.get('/api/health', (req, res) => {
  res.json({ success: true, message: 'ReadLater Server OK' });
});

// 启动
app.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════════════╗
║                                                ║
║   稍后再看 (ReadLater) 服务器已启动           ║
║                                                ║
║   地址: http://localhost:${PORT}                  ║
║   数据目录: ${DATA_DIR}          ║
║                                                ║
╚════════════════════════════════════════════════╝
  `);
});

// 优雅关闭
process.on('SIGINT', () => {
  console.log('\n正在关闭服务器...');
  db.close();
  process.exit(0);
});
