# 移动端 CI 镜像：Flutter 官方镜像 + Node + Android SDK/NDK/CMake + pub/Gradle 缓存
#
# 构建（context 是 mobile/）：
#   docker build -f mobile/ci/Dockerfile -t <registry>/readlater-android-ci:3.38.10 mobile
#
# 如果 Docker Hub 不可达，用本机已有的 Debian 版 node 镜像：
#   docker build --build-arg NODE_IMAGE=docker.m.daocloud.io/library/node:22 \
#     -f mobile/ci/Dockerfile -t <registry>/readlater-android-ci:3.38.10 mobile
#
# 如果需要 pub 镜像：
#   docker build --build-arg PUB_HOSTED_URL=https://pub.flutter-io.cn ...
#
# 说明：
# - ghcr.io/cirruslabs/flutter:3.38.10 自带 Flutter 3.38.10 / JDK 21 / Android SDK 36
# - 该镜像没有 node，actions/checkout、forgejo/upload-artifact 会报 node not found
# - 预先安装项目需要的 NDK / CMake / build-tools / platform，避免 CI 每次下载
# - 预热 pub 依赖、Gradle 发行包、Gradle/Maven 依赖缓存；CI 首次构建即可命中

ARG NODE_IMAGE=node:24-bookworm-slim
ARG PUB_HOSTED_URL=https://pub.dev

FROM ${NODE_IMAGE} AS node

FROM ghcr.io/cirruslabs/flutter:3.38.10 AS base
ARG PUB_HOSTED_URL

# 国内 Flutter 存储/pub 镜像；CI 里可用变量覆盖
ENV FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
ENV PUB_HOSTED_URL=${PUB_HOSTED_URL}

COPY --from=node /usr/local/bin/node /usr/local/bin/node
RUN node --version

# 预装 Android SDK 组件（Flutter 镜像已带 platform 36 / build-tools 36）
# 拆成多个 RUN，避免单个 Docker layer 过大导致 Nexus 上传超时
RUN yes | sdkmanager --licenses >/dev/null
RUN sdkmanager --install "platforms;android-34" "platforms;android-35"
RUN sdkmanager --install "build-tools;35.0.0"
RUN sdkmanager --install "ndk;28.2.13676358"
RUN sdkmanager --install "ndk;29.0.13599879"
RUN sdkmanager --install "cmake;3.22.1"

# 预热 Gradle 发行包（gradle-wrapper.properties 已指向腾讯镜像）
COPY android/gradlew /tmp/gradle-warm/gradlew
COPY android/gradle /tmp/gradle-warm/gradle
RUN chmod +x /tmp/gradle-warm/gradlew && \
    cd /tmp/gradle-warm && \
    ./gradlew --version && \
    rm -rf /tmp/gradle-warm

# 预热 pub 依赖（只复制 lockfile，不把源码打进最终镜像）
COPY pubspec.yaml pubspec.lock /tmp/pub-warm/
RUN cd /tmp/pub-warm && \
    PUB_HOSTED_URL="${PUB_HOSTED_URL}" flutter pub get && \
    rm -rf /tmp/pub-warm

# 预热 Gradle/Maven 依赖：临时复制整个 mobile 工程跑一次 debug 构建，
# 只把 /root/.gradle 和 /root/.pub-cache 带回最终镜像，源码不进最终层。
FROM base AS gradle-warm
ARG PUB_HOSTED_URL
COPY . /tmp/app
RUN cd /tmp/app && \
    PUB_HOSTED_URL="${PUB_HOSTED_URL}" flutter pub get && \
    flutter build apk --release \
      --target-platform android-arm64 \
      --split-per-abi

FROM base
COPY --from=gradle-warm /root/.gradle /root/.gradle
COPY --from=gradle-warm /root/.pub-cache /root/.pub-cache

# 验证
RUN flutter --version | head -2 && \
    node --version && \
    java -version && \
    sdkmanager --list_installed | grep -E 'ndk;|cmake;|platforms;android-3|build-tools;3'
