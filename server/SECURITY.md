# ReadLater 服务器安全指南

## 部署前安全检查清单

### 1. CORS 配置
**生产环境必须配置允许的来源**

```yaml
# docker-compose.yml
environment:
  - ALLOWED_ORIGINS=https://your-domain.com,chrome-extension://your-extension-id
```

### 2. 数据目录权限
确保数据目录有正确的权限：

```bash
# 设置正确的权限
chmod 700 /path/to/data
chown 1000:1000 /path/to/data
```

### 3. 反向代理配置（推荐）
使用 Nginx 或 Traefik 作为反向代理：

```nginx
server {
    listen 443 ssl http2;
    server_name readlater.your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # 限制请求体大小
    client_max_body_size 20M;

    # 安全头部
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 4. 防火墙配置
只开放必要的端口：

```bash
# 开放 HTTPS
sudo ufw allow 443/tcp

# 如果直接用 3000 端口（不推荐）
sudo ufw allow from YOUR_IP to any port 3000
```

## 安全特性

### 已实现的保护

1. **请求限流**
   - 通用接口：15 分钟 100 请求
   - API 操作：1 分钟 30 请求

2. **图片上传保护**
   - 最大 10MB 限制（可配置）
   - MIME 类型验证
   - 只允许图片格式：jpg, png, gif, webp, bmp

3. **路径遍历防护**
   - 文件名验证
   - 路径解析检查

4. **SQL 注入防护**
   - 使用参数化查询
   - 输入清理

5. **CORS 控制**
   - 可配置允许的来源
   - 生产环境默认拒绝

## 环境变量说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | 3000 | 服务器端口 |
| `DATA_DIR` | ./data | 数据存储目录 |
| `ALLOWED_ORIGINS` | * | CORS 允许来源 |
| `NODE_ENV` | development | 运行环境 |
| `MAX_IMAGE_SIZE_MB` | 10 | 图片大小限制 |

## 安全更新

保持依赖更新：

```bash
# 进入 server 目录
cd server

# 检查更新
npm outdated

# 更新依赖
npm update

# 重新构建 Docker 镜像
docker-compose up --build -d
```
