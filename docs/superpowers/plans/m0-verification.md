# M0 真机验证记录（Android 模拟器）

- 日期：2026-11-09
- 设备：Pixel_8 Android 模拟器（x86_64，1080×2400），本次未接入作者平板
- 应用：`mobile/` release APK（`app-x86_64-release.apk`），服务器 `server/` 本机 3999 端口
- 结论：**核心链路通过**；真机专属项（视频全屏、内存、真实站点图片/iframe）待作者平板复核

## 结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 1. 多标签保活 | 通过 | 新标签、切换、会话恢复（重启后恢复 Example Domain）正常；截图 `smoke-21-tabmenu.png` |
| 2. 视频全屏 | **未验证** | 模拟器无稳定视频站点；需作者平板复核 |
| 3. 长按链接弹菜单 | 通过 | 真实长按 `example.com` 的 "Learn more" 弹出菜单；"收藏到稍后再看"置顶、"收藏主站"第二（`smoke-9-sheet.png`、`smoke-16-sheet-enabled.png`） |
| 4. 截图 | 通过 | `takeScreenshot(JPEG 80)` 返回字节 → data URL；服务器落盘 `images/1794198347551_screenshot_br9a8ze.jpg`（183KB） |
| 5. 收藏链路 | 通过 | `POST /api/links` 成功；标题解析为 "Example Domains"，`source_page=https://example.com/`，`custom_data={"kind":"link","platform":"android"}` |
| 6. `onCreateWindow` / 下载提示 | **未验证** | 需真实站点触发；代码路径已实现，待作者平板复核 |
| 附加：站点收藏 | 通过 | 工具栏菜单收藏主站 → `/api/sites` 返回 `https://example.com`，站点页显示卡片 |
| 附加：收藏库/设置/回收站 | 通过 | 库列表显示已收藏项；设置页保存并测连接成功；回收站 UI 可打开 |

## 过程中发现并修复的问题

1. **截图未保存**：客户端直接 base64 编码未加 `data:image/...;base64,` 前缀，服务器 `processImage` 报 "Unknown format" 并丢弃。修复为 JPEG data URL（`imageDataUrl`），已复测落盘成功。
2. **收藏库列表为空**：`GET /api/links` 返回 `{ success, data: { data, total } }`，客户端按扁平结构解析。修复为兼容嵌套结构，已复测列表显示正常。
3. **配置后页面不刷新**：设置保存成功后未刷新收藏库/站点页，切换 tab 仍显示旧错误。已在保存与收藏成功后触发 `refresh()`。
4. **站点图标**：`example.com` 的 `<link rel="icon" href="data:,">` 被存成 `icon_url`；解析时过滤非 http(s) 图标，回退首字母占位。

## 待作者平板复核（M10 剩余项）

- B 站/YouTube 网页视频全屏、横屏与退出恢复；
- 5 个标签内存表现、后台标签资源占用；
- 真实站点（B 站等）附近图片提取与 blob 图片转换；
- 跨域 iframe 内链接（v1 已知不支持）；
- 返回键、旋转、深色模式下的实际观感。

## 2026-11-09 补充：Pixel Tablet 模拟器 + host GPU

- 新建 AVD Pixel_Tablet（system-images;android-36;google_apis_playstore;x86_64，Pixel Tablet 设备定义），启动参数 -gpu host；已确认进程命令行包含 -gpu host（此前 Pixel_8 用 swiftshader_indirect 软件渲染，是视频卡顿的主因）。
- 平板横向 2560×1600：收藏库/站点页使用左侧 NavigationRail，浏览器宽屏地址栏与标签条正常；Media3 全屏播放本地 MP4 正常。
- 平板纵向 1600×2560：布局仍为宽屏断点（NavigationRail），无溢出。
- 说明：模拟器视频解码仍是软件路径，高分辨率/高码率视频仍可能卡；直链视频在真机上的表现需以作者平板为准。
