# 标签页导入（Android Chromium）

从已连接的 Android 设备读取 Chrome / Brave / Edge / Chromium 当前打开的标签页，导入到 ReadLater。

## 前置条件

1. 手机/平板开启开发者选项与 USB 调试；
2. 保持浏览器运行，并至少打开一个普通网页标签；
3. 电脑能执行 adb；网络 ADB 先连接：

```bash
adb connect <手机IP>:5555
adb devices
```

## 用法

```bash
node tools/import-tabs/import.mjs \
  --server http://192.168.1.10:3000 \
  --api-key <API_KEY>
```

默认只导入 `url` 和 `title`。

### 多设备 / 指定浏览器

```bash
node tools/import-tabs/import.mjs --device 192.168.1.20:5555 ...
node tools/import-tabs/import.mjs --socket brave_devtools_remote ...
```

### 尝试导入页面截图

```bash
node tools/import-tabs/import.mjs --with-screenshots ...
```

说明：

- `/json/list` 本身没有 Chrome 标签页切换器的缩略图；截图是通过 CDP `Page.captureScreenshot` 对每个标签页单独截的，作为链接的 `screenshot` 字段；
- 工具默认**不会激活或切换标签页**；后台标签页可能得到旧帧/空白，截图失败会跳过该标签页；
- 截图会先上传到 `/api/upload`，再随导入请求保存；
- 标签页很多时用 `--concurrency <n>` 调整截图并发（默认 3，最大 8）；
- 服务端单次导入上限 5000 条；工具会自动分批，`--batch-size` 可调（默认 5000，最大 5000）；
- 该截图是“页面截图”，不是原生标签页预览图。

### 只查看不导入

```bash
node tools/import-tabs/import.mjs ... --dry-run
```

## 环境变量

- `READLATER_SERVER`
- `READLATER_API_KEY`
- `ADB`（adb 路径）

## 已知限制

- 仅支持启用 DevTools remote debugging 的 Chromium 系浏览器；
- Chrome 首次启动向导未完成时可能没有 `*_devtools_remote` socket；
- 不支持 Firefox；
- 截图需要额外时间，标签页多时建议先不加 `--with-screenshots`。
