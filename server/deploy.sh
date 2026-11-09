#!/bin/bash
# ReadLater 服务器一键部署脚本（Linux/Mac）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/server/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/server/.env"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检测 docker compose 命令
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo -e "${RED}错误：未检测到 docker compose 命令，请先安装 Docker。${NC}"
  exit 1
fi

# 检查 .env 文件
if [ ! -f "$ENV_FILE" ]; then
  echo -e "${YELLOW}首次部署，正在创建 .env 配置文件...${NC}"
  if [ -f "${SCRIPT_DIR}/.env.example" ]; then
    cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
  else
    echo -e "${RED}错误：找不到 ${SCRIPT_DIR}/.env.example 模板文件。${NC}"
    exit 1
  fi
  echo -e "${YELLOW}请编辑 ${ENV_FILE} 设置 API_KEY，然后重新运行本脚本。${NC}"
  exit 0
fi

# 加载 .env 到当前 shell
set -a
source "$ENV_FILE"
set +a

# 检查 API_KEY 是否已设置
if [ -z "$API_KEY" ]; then
  echo -e "${RED}错误：未在 ${ENV_FILE} 中设置 API_KEY。${NC}"
  echo -e "${YELLOW}请先生成密钥：openssl rand -base64 32${NC}"
  echo -e "${YELLOW}然后编辑 ${ENV_FILE} 填写 API_KEY。${NC}"
  exit 1
fi

echo -e "${GREEN}开始部署 ReadLater 服务器...${NC}"

# 创建数据目录（路径基于 docker-compose.yml 所在目录解析）
COMPOSE_DIR="$(dirname "$COMPOSE_FILE")"
DATA_PATH="${DATA_PATH:-./data}"
if [[ "$DATA_PATH" != /* ]]; then
  DATA_PATH="${COMPOSE_DIR}/${DATA_PATH}"
fi
mkdir -p "$DATA_PATH"

cd "$PROJECT_ROOT"

# 根据 DOCKER_REGISTRY 决定是否拉取预构建镜像
if [ -n "$DOCKER_REGISTRY" ]; then
  echo -e "${GREEN}使用预构建镜像：${DOCKER_REGISTRY}/read-later-server:latest${NC}"
  ${COMPOSE_CMD} -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
else
  echo -e "${GREEN}本地构建镜像...${NC}"
fi

${COMPOSE_CMD} -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

echo -e "${GREEN}部署完成！${NC}"
echo ""
echo "服务状态："
${COMPOSE_CMD} -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

echo ""
echo -e "${GREEN}健康检查：${NC}"
PORT="${PORT:-3000}"
sleep 2
curl -s "http://localhost:${PORT}/api/health" || true

echo ""
echo -e "${YELLOW}查看日志：${COMPOSE_CMD} -f ${COMPOSE_FILE} --env-file ${ENV_FILE} logs -f${NC}"
