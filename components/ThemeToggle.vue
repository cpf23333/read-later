<script lang="ts" setup>
import { useTheme } from '@/utils/theme';

const { setTheme, resolvedTheme } = useTheme();
</script>

<template>
  <div class="theme-toggle" title="切换主题">
    <button
      v-if="resolvedTheme === 'dark'"
      class="theme-btn"
      @click="setTheme('light')"
      aria-label="切换到浅色模式"
    >
      🌙
    </button>
    <button
      v-else
      class="theme-btn"
      @click="setTheme('dark')"
      aria-label="切换到深色模式"
    >
      ☀️
    </button>
  </div>
</template>

<style scoped>
.theme-toggle {
  display: inline-flex;
}

.theme-btn {
  width: 36px;
  height: 36px;
  border-radius: var(--rl-radius-md);
  border: 1px solid var(--rl-border);
  background: var(--rl-bg-elevated);
  color: var(--rl-text);
  font-size: 16px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.theme-btn:hover {
  background: var(--rl-bg-hover);
  border-color: var(--rl-border-strong);
}
</style>
