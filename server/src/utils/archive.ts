/**
 * 归档工具 - 打包数据库和图片目录
 */

import fs from 'fs';
import { ZipArchive } from 'archiver';

/**
 * 创建备份压缩包（包含数据库文件和图片目录）
 */
export async function createBackupArchive(
  dbPath: string,
  imagesDir: string,
  outputPath: string
): Promise<void> {
  return new Promise((resolve, reject) => {
    const output = fs.createWriteStream(outputPath);
    const archive = new ZipArchive({ zlib: { level: 6 } });

    output.on('close', () => {
      console.log(`[archive] Created: ${outputPath} (${archive.pointer()} bytes)`);
      resolve();
    });

    archive.on('error', (err: Error) => {
      reject(err);
    });

    archive.on('warning', (err: Error & { code?: string }) => {
      if (err.code === 'ENOENT') {
        console.warn('[archive] Warning:', err.message);
      } else {
        reject(err);
      }
    });

    archive.pipe(output);

    // 添加数据库文件
    if (fs.existsSync(dbPath)) {
      archive.file(dbPath, { name: 'readlater.db' });
    }

    // 添加 images 目录
    if (fs.existsSync(imagesDir)) {
      archive.directory(imagesDir, 'images');
    }

    archive.finalize();
  });
}
