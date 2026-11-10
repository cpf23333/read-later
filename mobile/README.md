# ReadLater 移动端

Android 版“稍后再看”客户端：内置多标签浏览器、收藏库、站点收藏、视频播放和设置页。

## 开发

```bash
cd mobile
flutter pub get
flutter run
```

常用检查：

```bash
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

发布/侧载 APK：

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

包名：`com.cpf23333.readlater`，`minSdk 26`。

## 首次使用

1. 打开“设置”，填写服务器地址和 API Key；
2. 保存并测试连接；
3. 在“浏览器”里收藏链接，或从现有浏览器导入。

## 从电脑浏览器导入标签页

脚本**不在 APK 里，也不在 `mobile/` 目录中**，而在仓库根目录：

```text
tools/import-tabs/import.mjs
```

获取方式：克隆整个仓库，或从仓库单独下载这个文件。脚本只依赖 Node 内置模块，不需要 `npm install`。

要求：

- 电脑有 Node.js 24+ 和 adb；
- 手机/平板开启 USB 调试；
- Chrome / Edge / Brave 等 Chromium 浏览器保持标签页打开。

### 方式一：导出 ZIP，传到手机导入（推荐）

```bash
# 在仓库根目录执行
node tools/import-tabs/import.mjs \
  --with-screenshots \
  --export readlater-tabs.zip
```

- 不需要服务器地址或 API Key；
- `--with-screenshots` 可选，会把每个标签页截图一起打进 ZIP；
- 浏览器不在默认 socket 时加 `--socket brave_devtools_remote` 等；
- 多设备时加 `--device <adb serial>`。

然后把 `readlater-tabs.zip` 传到手机（USB、网盘、聊天工具均可），在 App：

```text
设置 → 从压缩包导入标签页 → 选择 readlater-tabs.zip
```

App 会解析 manifest、预览标签页和截图，再分批写入服务器。预览最多显示前 50 条，导入是全部；单次 ZIP 上限 200MB / 5000 条。

### 方式二：电脑直接导入服务器

```bash
adb forward tcp:9222 localabstract:chrome_devtools_remote

node tools/import-tabs/import.mjs \
  --server http://<服务器地址> \
  --api-key <API Key>
```

这种方式直接在当前电脑上把标签页 POST 到服务器，适合临时迁移。

### 已知限制

- 只支持 Chromium 系浏览器（Chrome / Edge / Brave 等），不支持 Firefox；
- 只读取已打开标签页，不读历史记录/书签；
- 截图是 CDP 页面截图，不是浏览器原生标签页缩略图；
- 免电脑方案（手机内网络 ADB / Shizuku）已实测受 SELinux 限制，非 root 不可用，因此 App 不内置导入；
- 更完整的脚本参数见 [tools/import-tabs/README.md](../tools/import-tabs/README.md)。

## 相关文档

- 设计：[docs/superpowers/specs/2026-11-09-readlater-mobile-flutter-design.md](../docs/superpowers/specs/2026-11-09-readlater-mobile-flutter-design.md)
- 计划：[docs/superpowers/plans/2026-11-09-mobile-app-v1.md](../docs/superpowers/plans/2026-11-09-mobile-app-v1.md)
