/**
 * 应用设置路由
 *
 * GET   /api/settings/user-agent   获取全局默认 User-Agent
 * PATCH /api/settings/user-agent   更新全局默认 User-Agent
 */

import { Hono } from 'hono';
import { apiRateLimit } from '../middleware/ratelimit.ts';
import {
  getDefaultUserAgentSetting,
  setDefaultUserAgentSetting,
} from '../utils/database.ts';
import type {
  ApiResponse,
  UserAgentMode,
  UserAgentSetting,
} from '../types/index.ts';

const app = new Hono();

function normalizeMode(value: unknown): UserAgentMode | undefined {
  return value === 'default' || value === 'desktop' || value === 'custom'
    ? value
    : undefined;
}

app.get('/user-agent', async (c) => {
  return c.json<ApiResponse<UserAgentSetting>>({
    success: true,
    data: getDefaultUserAgentSetting(),
  });
});

app.patch('/user-agent', apiRateLimit, async (c) => {
  const body = await c.req
    .json<{ user_agent_mode?: unknown; user_agent?: unknown }>()
    .catch(() => null);
  if (!body) {
    return c.json<ApiResponse>({ success: false, error: 'Invalid body' }, 400);
  }

  const mode = normalizeMode(body.user_agent_mode);
  if (!mode) {
    return c.json<ApiResponse>(
      { success: false, error: 'Invalid user_agent_mode' },
      400
    );
  }
  const custom =
    typeof body.user_agent === 'string' && body.user_agent.trim()
      ? body.user_agent.trim()
      : null;
  if (mode === 'custom' && !custom) {
    return c.json<ApiResponse>(
      { success: false, error: 'user_agent is required for custom mode' },
      400
    );
  }

  const setting: UserAgentSetting = {
    user_agent_mode: mode,
    user_agent: mode === 'custom' ? custom : null,
  };
  setDefaultUserAgentSetting(setting);
  return c.json<ApiResponse<UserAgentSetting>>({ success: true, data: setting });
});

export default app;
