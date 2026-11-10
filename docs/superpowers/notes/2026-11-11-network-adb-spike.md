# 网络 ADB / Shizuku 标签页导入评估记录

日期：2026-11-11

## 结论

**不可行（非 root）。** 保留 PC + adb `forward` 的导入方案作为唯一可用路径。

## 已尝试路径

### Android 11+ 无线调试 + 纯 Dart ADB 客户端

- 使用 `flutter_adb` 完成无线调试配对；
- 在 Xiaomi 15 Pro（Android 16）上配对成功；
- ADB 连接成功，`shell` 能列出：

```text
@chrome_devtools_remote
```

- 但 app 直接：

```dart
connection.open('localabstract:chrome_devtools_remote')
```

失败：

```text
Stream open failed or refused by remote peer
```

### adbd shell + app_process helper

- 将 `AdbProxy` 类打进 APK；
- 通过 ADB shell 执行 `app_process`，以 shell 身份连接 abstract socket；
- 结果：

```text
java.io.IOException: Permission denied
at android.net.LocalSocketImpl.connectLocal(Native Method)
at android.net.LocalSocket.connect(LocalSocket.java:162)
```

### Shizuku（非 root，adb 启动）

- 安装 Shizuku 13.x；
- 通过无线调试配对成功，Shizuku 状态显示运行中；
- `rish` 执行 `id`：

```text
uid=2000(shell) ... context=u:r:shell:s0
```

- `rish` 能看到 `@chrome_devtools_remote`；
- 用 `rish` 启动同样的 helper，仍得到：

```text
java.io.IOException: Permission denied
```

## 根因

Chrome/Edge 的 `chrome_devtools_remote` 是 abstract Unix socket，SELinux 拒绝 shell/app 域连接。电脑 `adb forward` 能工作，是因为连接由 adbd 以特权上下文打开，而不是普通 shell 进程。

## 决定

- 移除 app 内网络 ADB 配对入口和 `flutter_adb` 依赖；
- 移除实验性的 shell helper；
- 保留 `tools/import-tabs`（PC adb + CDP）作为导入工具；
- 若未来支持免电脑导入，需要 root，或找到不依赖 shell 连接 Chrome socket 的官方接口。
