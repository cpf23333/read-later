/**
 * 稍后再看 - SQLite 后端服务
 *
 * 启动: npm start
 * 默认端口: 3000
 */

const express = require("express");
const Database = require("better-sqlite3");
const cors = require("cors");
const path = require("path");
const fs = require("fs");

const app = express();
const PORT = process.env.PORT || 3000;
const DATA_DIR = process.env.DATA_DIR || "./data";

// 确保数据目录存在
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 图片存储目录
const IMAGES_DIR = path.join(DATA_DIR, "images");
const DELETED_IMAGES_DIR = path.join(DATA_DIR, "images", "deleted");

if (!fs.existsSync(IMAGES_DIR)) {
  fs.mkdirSync(IMAGES_DIR, { recursive: true });
}
if (!fs.existsSync(DELETED_IMAGES_DIR)) {
  fs.mkdirSync(DELETED_IMAGES_DIR, { recursive: true });
}

// 初始化 SQLite 数据库
const db = new Database(path.join(DATA_DIR, "readlater.db"));

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

// 辅助函数：将 Base64 保存为文件
function saveBase64ToFile(base64Data, prefix) {
  try {
    console.log("[saveBase64ToFile] Input length:", base64Data.length);
    console.log("[saveBase64ToFile] Prefix:", prefix);

    const cleanBase64 = base64Data.replace(/^data:image\/\w+;base64,/, "");
    console.log("[saveBase64ToFile] After regex, length:", cleanBase64.length);

    const buffer = Buffer.from(cleanBase64, "base64");
    console.log("[saveBase64ToFile] Buffer size:", buffer.length);

    // 根据 prefix 选择扩展名
    const ext = prefix === "screenshot" ? "jpg" : "png";
    const filename = `${Date.now()}_${prefix}_${Math.random().toString(36).substr(2, 9)}.${ext}`;
    const filepath = path.join(IMAGES_DIR, filename);

    console.log("[saveBase64ToFile] Saving to:", filepath);
    fs.writeFileSync(filepath, buffer);
    console.log("[saveBase64ToFile] Saved successfully:", filename);

    return filename;
  } catch (error) {
    console.error("[saveBase64ToFile] Failed to save image:", error.message);
    console.error(error.stack);
    return null;
  }
}

// 中间件
app.use(cors());
app.use(express.json({ limit: "50mb" }));
app.use("/images", express.static(IMAGES_DIR));
app.use("/images/deleted", express.static(DELETED_IMAGES_DIR));

// ===== 链接 API =====

// 获取所有链接
app.get("/api/links", (req, res) => {
  try {
    const {
      page = 1,
      pageSize = 50,
      sortBy = "created_at",
      sortOrder = "desc",
      search,
      domain,
    } = req.query;

    let sql = "SELECT * FROM links";
    let countSql = "SELECT COUNT(*) as count FROM links";
    const params = [];
    const conditions = [];

    // 搜索条件
    if (search) {
      conditions.push("(url LIKE ? OR title LIKE ? OR source_page LIKE ?)");
      const searchParam = `%${search}%`;
      params.push(searchParam, searchParam, searchParam);
    }

    // 域名过滤
    if (domain) {
      conditions.push("source_page LIKE ?");
      params.push(`%${domain}%`);
    }

    // 添加 WHERE 子句
    if (conditions.length > 0) {
      const whereClause = " WHERE " + conditions.join(" AND ");
      sql += whereClause;
      countSql += whereClause;
    }

    // 排序和分页
    sql += ` ORDER BY ${sortBy} ${sortOrder === "asc" ? "ASC" : "DESC"}`;
    const offset = (page - 1) * pageSize;
    sql += " LIMIT ? OFFSET ?";
    params.push(parseInt(pageSize), parseInt(offset));

    const links = db
      .prepare(sql)
      .all(...params.slice(0, -2).concat(params.slice(-2)));
    const total =
      conditions.length > 0
        ? db.prepare(countSql).all(...params.slice(0, -2))[0].count
        : db.prepare(countSql).get().count;

    // 日志输出第一个链接的图片字段
    if (links.length > 0) {
      console.log("[getLinks] First link images:", {
        url: links[0].url,
        nearby_image: links[0].nearby_image,
        screenshot: links[0].screenshot,
      });
    }

    res.json({ success: true, data: links, total });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 搜索链接
app.get("/api/search", (req, res) => {
  try {
    const { q } = req.query;
    if (!q) {
      return res.json({ success: true, data: [] });
    }

    const searchParam = `%${q}%`;
    const links = db
      .prepare(
        `
      SELECT * FROM links 
      WHERE url LIKE ? OR title LIKE ? OR source_page LIKE ?
      ORDER BY created_at DESC
    `,
      )
      .all(searchParam, searchParam, searchParam);

    res.json({ success: true, data: links });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 获取域名统计
app.get("/api/domains", (req, res) => {
  try {
    const links = db.prepare("SELECT source_page FROM links").all();
    const domainCounts = new Map();

    for (const link of links) {
      try {
        const domain = new URL(link.source_page).hostname;
        if (domain) {
          domainCounts.set(domain, (domainCounts.get(domain) || 0) + 1);
        }
      } catch {
        // 忽略无效URL
      }
    }

    const result = Array.from(domainCounts.entries())
      .map(([domain, count]) => ({ domain, count }))
      .sort((a, b) => b.count - a.count);

    res.json({ success: true, data: result });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 辅助函数：下载网络图片
async function downloadImage(url, prefix) {
  try {
    const response = await fetch(url, {
      timeout: 10000,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      },
    });

    if (!response.ok) {
      console.warn(`[downloadImage] Failed: HTTP ${response.status}`);
      return null;
    }

    const contentType = response.headers.get("content-type");
    if (!contentType || !contentType.startsWith("image/")) {
      console.warn(`[downloadImage] Not an image: ${contentType}`);
      return null;
    }

    const buffer = Buffer.from(await response.arrayBuffer());

    // 5MB 限制
    if (buffer.length > 5 * 1024 * 1024) {
      console.warn(`[downloadImage] Too large: ${buffer.length} bytes`);
      return null;
    }

    const ext =
      prefix === "screenshot"
        ? "jpg"
        : contentType.includes("png")
          ? "png"
          : "jpg";
    const filename = `${Date.now()}_${prefix}_${Math.random().toString(36).substr(2, 9)}.${ext}`;
    const filepath = path.join(IMAGES_DIR, filename);

    fs.writeFileSync(filepath, buffer);
    console.log(`[downloadImage] Saved: ${filename}`);
    return filename;
  } catch (error) {
    console.error(`[downloadImage] Error:`, error.message);
    return null;
  }
}

// 辅助函数：保存图片并返回路径
async function processImage(imageData, prefix) {
  if (!imageData) return null;

  console.log(`[processImage] ${prefix}:`, imageData.substring(0, 60) + "...");

  // 如果已经是路径，直接返回
  if (imageData.startsWith("/images/")) {
    return imageData;
  }

  // 如果是 Base64，保存为文件
  if (imageData.startsWith("data:image")) {
    const filename = saveBase64ToFile(imageData, prefix);
    return filename ? `/images/${filename}` : null;
  }

  // 如果是网络图片 URL，下载并保存
  if (imageData.startsWith("http://") || imageData.startsWith("https://")) {
    console.log(`[processImage] Downloading ${prefix}...`);
    const filename = await downloadImage(imageData, prefix);
    return filename ? `/images/${filename}` : null;
  }

  console.log(`[processImage] Unknown format for ${prefix}`);
  return null;
}

// 添加链接
app.post("/api/links", async (req, res) => {
  try {
    const {
      id,
      url,
      title,
      nearby_image,
      screenshot,
      source_page,
      created_at,
      custom_data,
    } = req.body;

    console.log("[Server] Received link:", {
      url,
      nearby_image: nearby_image ? `${nearby_image.substring(0, 50)}...` : null,
      screenshot: screenshot ? `${screenshot.substring(0, 50)}...` : null,
    });

    // 处理图片：如果是 Base64 则保存为文件
    const nearbyImagePath = await processImage(nearby_image, "nearby");
    const screenshotPath = await processImage(screenshot, "screenshot");

    console.log("[Server] Processed images:", {
      nearbyImagePath,
      screenshotPath,
    });

    const now = Date.now();
    db.prepare(
      `
      INSERT INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    ).run(
      id || `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      url,
      title || "",
      nearbyImagePath,
      screenshotPath,
      source_page || "",
      created_at || now,
      now,
      JSON.stringify(custom_data || {}),
    );

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 批量添加链接
app.post("/api/links/batch", async (req, res) => {
  try {
    const { links } = req.body;
    const insert = db.prepare(`
      INSERT OR REPLACE INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    for (const item of links) {
      // 处理图片
      const nearbyImagePath = await processImage(
        item.nearby_image || item.nearbyImage,
        "nearby",
      );
      const screenshotPath = await processImage(item.screenshot, "screenshot");

      insert.run(
        item.id,
        item.url,
        item.title || "",
        nearbyImagePath,
        screenshotPath,
        item.source_page || item.sourcePage || "",
        item.created_at || item.createdAt || Date.now(),
        Date.now(),
        JSON.stringify(item.custom_data || item.customData || {}),
      );
    }

    res.json({ success: true, count: links.length });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 删除链接（移入回收站）
app.delete("/api/links/:id", (req, res) => {
  try {
    const link = db
      .prepare("SELECT * FROM links WHERE id = ?")
      .get(req.params.id);
    if (!link) {
      return res.status(404).json({ success: false, error: "Link not found" });
    }

    // 移入回收站
    const trashId = `delete_${link.id}_${Date.now()}`;
    db.prepare(
      `
      INSERT INTO trash (id, link_id, url, title, nearby_image, screenshot, source_page, created_at, deleted_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    ).run(
      trashId,
      link.id,
      link.url,
      link.title,
      link.nearby_image,
      link.screenshot,
      link.source_page,
      link.created_at,
      Date.now(),
      link.custom_data,
    );

    // 从主表删除
    db.prepare("DELETE FROM links WHERE id = ?").run(req.params.id);

    // 移动图片到 deleted 文件夹（保持原文件名）
    [link.nearby_image, link.screenshot].forEach((imgPath) => {
      if (imgPath && imgPath.startsWith("/images/")) {
        const filename = path.basename(imgPath);
        const oldPath = path.join(IMAGES_DIR, filename);
        const newPath = path.join(DELETED_IMAGES_DIR, filename);
        let isFileExist = fs.existsSync(oldPath);
        if (isFileExist) {
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

app.get("/api/trash", (req, res) => {
  try {
    const items = db
      .prepare("SELECT * FROM trash ORDER BY deleted_at DESC")
      .all();
    // 转换图片路径为 deleted 目录
    const itemsWithFixedPaths = items.map((item) => ({
      ...item,
      nearby_image:
        item.nearby_image && item.nearby_image.startsWith("/images/")
          ? item.nearby_image.replace("/images/", "/images/deleted/")
          : item.nearby_image,
      screenshot:
        item.screenshot && item.screenshot.startsWith("/images/")
          ? item.screenshot.replace("/images/", "/images/deleted/")
          : item.screenshot,
    }));
    res.json({ success: true, data: itemsWithFixedPaths });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post("/api/trash/:id/restore", (req, res) => {
  try {
    const item = db
      .prepare("SELECT * FROM trash WHERE id = ?")
      .get(req.params.id);
    if (!item)
      return res.status(404).json({ success: false, error: "Not found" });

    const newId = `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    db.prepare(
      `
      INSERT INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    ).run(
      newId,
      item.url,
      item.title,
      item.nearby_image,
      item.screenshot,
      item.source_page,
      Date.now(),
      Date.now(),
      item.custom_data,
    );

    db.prepare("DELETE FROM trash WHERE id = ?").run(req.params.id);

    // 还原图片（保持原文件名）
    [item.nearby_image, item.screenshot].forEach((imgPath) => {
      if (imgPath && imgPath.startsWith("/images/")) {
        const filename = path.basename(imgPath);
        const oldPath = path.join(DELETED_IMAGES_DIR, filename);
        const newPath = path.join(IMAGES_DIR, filename);
        if (fs.existsSync(oldPath)) {
          fs.renameSync(oldPath, newPath);
        }
      }
    });

    res.json({ success: true, data: { newId } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete("/api/trash/:id", (req, res) => {
  try {
    const item = db
      .prepare("SELECT * FROM trash WHERE id = ?")
      .get(req.params.id);
    if (item) {
      // 删除图片（使用原文件名）
      [item.nearby_image, item.screenshot].forEach((imgPath) => {
        if (imgPath && imgPath.startsWith("/images/")) {
          const filename = path.basename(imgPath);
          const filePath = path.join(DELETED_IMAGES_DIR, filename);
          if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
        }
      });
    }

    db.prepare("DELETE FROM trash WHERE id = ?").run(req.params.id);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 图片上传 API（保留兼容）=====

app.post("/api/upload", async (req, res) => {
  try {
    const { image, filename } = req.body;
    if (!image)
      return res.status(400).json({ success: false, error: "No image" });

    const result = await processImage(image, "upload");
    if (!result) {
      return res
        .status(400)
        .json({ success: false, error: "Invalid image data" });
    }

    res.json({ success: true, data: { url: result } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 统计 API =====

app.get("/api/stats", (req, res) => {
  try {
    const linkCount = db
      .prepare("SELECT COUNT(*) as count FROM links")
      .get().count;
    const trashCount = db
      .prepare("SELECT COUNT(*) as count FROM trash")
      .get().count;

    res.json({ success: true, data: { linkCount, trashCount } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ===== 导出/导入 API =====

app.get("/api/export", (req, res) => {
  try {
    const links = db.prepare("SELECT * FROM links").all();
    res.json({ success: true, data: links });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post("/api/import", async (req, res) => {
  try {
    const { links, mode = "merge" } = req.body;

    if (mode === "replace") {
      db.prepare("DELETE FROM links").run();
    }

    const stmt = db.prepare(`
      INSERT OR IGNORE INTO links (id, url, title, nearby_image, screenshot, source_page, created_at, updated_at, custom_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    let imported = 0;
    for (const item of links) {
      try {
        // 处理图片
        const nearbyImagePath = await processImage(
          item.nearby_image || item.nearbyImage,
          "nearby",
        );
        const screenshotPath = await processImage(
          item.screenshot,
          "screenshot",
        );

        stmt.run(
          item.id || `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          item.url,
          item.title || "",
          nearbyImagePath,
          screenshotPath,
          item.source_page || item.sourcePage || "",
          item.created_at || item.createdAt || Date.now(),
          Date.now(),
          JSON.stringify(item.custom_data || item.customData || {}),
        );
        imported++;
      } catch (e) {}
    }
    res.json({ success: true, data: { imported, total: links.length } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// 健康检查
app.get("/api/health", (req, res) => {
  res.json({ success: true, message: "ReadLater Server OK" });
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
process.on("SIGINT", () => {
  console.log("\n正在关闭服务器...");
  db.close();
  process.exit(0);
});
