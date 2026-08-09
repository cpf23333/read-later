/**
 * ReadLater 类型定义
 */

// 链接数据结构
export interface Link {
  id: string;
  url: string;
  title: string;
  nearby_image: string | null;
  screenshot: string | null;
  source_page: string | null;
  created_at: number;
  updated_at: number | null;
  custom_data: string | null;
}

// 回收站数据结构
export interface TrashItem {
  id: string;
  link_id: string;
  url: string;
  title: string;
  nearby_image: string | null;
  screenshot: string | null;
  source_page: string | null;
  created_at: number;
  deleted_at: number;
  custom_data: string | null;
}

// API 响应格式
export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
}

// 链接列表查询参数
export interface LinkQueryParams {
  page?: string;
  pageSize?: string;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
  search?: string;
  domain?: string;
}

// 添加链接请求体
export interface CreateLinkBody {
  id?: string;
  url: string;
  title?: string;
  nearby_image?: string;
  screenshot?: string;
  source_page?: string;
  created_at?: number;
  custom_data?: Record<string, unknown>;
}

// 批量添加请求体
export interface BatchCreateBody {
  links: Array<{
    id?: string;
    url: string;
    title?: string;
    nearby_image?: string;
    nearbyImage?: string;
    screenshot?: string;
    source_page?: string;
    sourcePage?: string;
    created_at?: number;
    createdAt?: number;
    custom_data?: Record<string, unknown>;
    customData?: Record<string, unknown>;
  }>;
}

// 导入请求体
export interface ImportBody {
  links: Array<{
    id?: string;
    url: string;
    title?: string;
    nearby_image?: string;
    nearbyImage?: string;
    screenshot?: string;
    source_page?: string;
    sourcePage?: string;
    created_at?: number;
    createdAt?: number;
    custom_data?: string | Record<string, unknown>;
    customData?: string | Record<string, unknown>;
  }>;
  mode?: 'merge' | 'replace';
}

// 上传图片请求体
export interface UploadBody {
  image: string;
  filename?: string;
}

// 统计数据
export interface Stats {
  linkCount: number;
  trashCount: number;
}

// 域名统计
export interface DomainStat {
  domain: string;
  count: number;
}

// 分页响应
export interface PaginatedResponse<T> {
  data: T[];
  total: number;
}

// 导出任务
export interface ExportTask {
  id: string;
  status: 'running' | 'completed' | 'failed';
  created_at: number;
  completed_at: number | null;
  filename: string | null;
  file_path: string | null;
  file_size: number | null;
  error: string | null;
}

// 环境变量
export interface Env {
  PORT: string;
  DATA_DIR: string;
  API_KEY: string;
  ALLOWED_ORIGINS: string;
  NODE_ENV: 'development' | 'production';
  MAX_IMAGE_SIZE_MB: string;
}
