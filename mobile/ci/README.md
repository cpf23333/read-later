# 移动端 CI 镜像

`readlater-android-ci` 基于 `ghcr.io/cirruslabs/flutter:3.38.10`，预装：

- Flutter 3.38.10 / JDK 21 / Android SDK 36
- NDK 28.2 / 29.0、CMake 3.22.1
- Node（供 Gitea/Forgejo JS action 使用）
- pub cache、Gradle wrapper 和 Gradle 依赖缓存
- vendored libmpv jar（media_kit Android 播放）

## 构建并推送

## 本地配置

本地构建前复制模板并填写 Nexus 地址：

```bash
cd mobile/ci
cp .env.example .env
```

`.env` 已被 `.gitignore` 忽略，脚本会自动读取；Forgejo Action 不读它，
Action 使用仓库 Variables。

模板内容：

```
CI_REGISTRY=<nexus-host>:8083
SDK_TEST_BASE_URL=http://<nexus-host>:8081/repository/android-sdk-raw/
SDK_IMAGE=<nexus-host>:8083/readlater-android-sdk:<sdk-tag>
PUB_HOSTED_URL=http://<nexus-host>:8081/repository/pub-proxy
NODE_IMAGE=docker.m.daocloud.io/library/node:22
FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.38.10
```

## 构建

先构建 Android SDK 基础镜像（只需要在能访问 Google 或 Nexus 的机器上做一次）：

Linux/macOS：

```bash
cd mobile/ci
./build-sdk.sh
```

Windows：

```bat
cd mobile\ci
build-sdk.bat
```

不传版本时会自动生成 `<Flutter 版本>-<UTC 时间戳>`，例如
`3.38.10-20261110-1509`。脚本最后会打印实际 tag；把这个 tag 写回
`.env` 的 `SDK_IMAGE`。

然后构建 CI 镜像：

```bash
cd mobile/ci
./build-and-push.sh 3.38.10-r2
```

```bat
cd mobile\ci
build-and-push.bat 3.38.10-r2
```

只推送本地已构建镜像（构建成功后推送超时时用）：

```bat
build-and-push.bat 3.38.10-r2 --push-only
```

只构建不推送：

```bat
build-and-push.bat 3.38.10-r2 --build-only
```

推送默认重试 5 次，可用 `PUSH_RETRIES` 调整：

```bat
set PUSH_RETRIES=10
build-and-push.bat 3.38.10-r2 --push-only
```

也可以用环境变量指定仓库：

```bash
CI_REGISTRY=<nexus-host>:8083 \
NODE_IMAGE=docker.m.daocloud.io/library/node:22 \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
./build-and-push.sh 3.38.10-r2
```

## 版本约定

不传版本参数时，脚本会自动生成：

```
3.38.10-20261110-1425
```

即 `<Flutter 版本>-<UTC 时间戳>`；同一天多次构建也会得到不同 tag，避免 dind 命中旧镜像。也可以显式传版本：

```bash
./build-and-push.sh 3.38.10-r2
```

- `3.38.10` 是 Flutter 版本
- 时间戳/`rN` 是镜像自身修订
- 镜像内写入 `READLATER_CI_VERSION`，workflow 启动时校验
- 重建后记得把脚本输出的 tag 同步到 Forgejo 变量

## 构建后更新

Forgejo Variables：

```
MOBILE_CI_IMAGE         = <nexus-host>:8083/readlater-android-ci:3.38.10-r2
MOBILE_CI_IMAGE_VERSION = 3.38.10-r2
```

刷新 runner 的 `docker_dind`：

```bash
docker exec docker_dind docker rmi <nexus-host>:8083/readlater-android-ci:3.38.10-r2 || true
docker exec docker_dind docker pull <nexus-host>:8083/readlater-android-ci:3.38.10-r2
```

## 注意事项

- 构建上下文是 `mobile/`，不是仓库根目录；脚本已处理。
- `mobile/third_party/media_kit_libs_android_video` 里的 libmpv jar 必须一起提交，否则 Gradle 会尝试从 GitHub 下载。
- Docker Hub 不可达时用 `NODE_IMAGE=docker.m.daocloud.io/library/node:22`。
