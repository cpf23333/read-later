import { ref, watch, type Ref } from 'vue';

export type Theme = 'light' | 'dark' | 'auto';

const STORAGE_KEY = 'readlater-theme';

function getSystemTheme(): 'light' | 'dark' {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function applyTheme(theme: Theme) {
  const resolved = theme === 'auto' ? getSystemTheme() : theme;
  document.documentElement.setAttribute('data-theme', resolved);
}

export function useTheme(): {
  theme: Ref<Theme>;
  setTheme: (t: Theme) => void;
  toggleTheme: () => void;
  resolvedTheme: Ref<'light' | 'dark'>;
} {
  const theme = ref<Theme>('auto');
  const resolvedTheme = ref<'light' | 'dark'>(getSystemTheme());

  // 从 storage 加载主题设置
  browser.storage.local
    .get(STORAGE_KEY)
    .then((result) => {
      const stored = result[STORAGE_KEY] as Theme | undefined;
      if (stored && ['light', 'dark', 'auto'].includes(stored)) {
        theme.value = stored;
      }
      applyTheme(theme.value);
      resolvedTheme.value = theme.value === 'auto' ? getSystemTheme() : theme.value;
    })
    .catch((error) => {
      console.warn('[Theme] Failed to load theme:', error);
    });

  function setTheme(newTheme: Theme) {
    theme.value = newTheme;
    applyTheme(newTheme);
    resolvedTheme.value = newTheme === 'auto' ? getSystemTheme() : newTheme;
    browser.storage.local.set({ [STORAGE_KEY]: newTheme }).catch((error) => {
      console.warn('[Theme] Failed to save theme:', error);
    });
  }

  function toggleTheme() {
    const next: Theme = resolvedTheme.value === 'dark' ? 'light' : 'dark';
    setTheme(next);
  }

  // 监听系统主题变化（auto 模式下需要响应）
  if (typeof window !== 'undefined') {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', () => {
      if (theme.value === 'auto') {
        applyTheme('auto');
        resolvedTheme.value = getSystemTheme();
      }
    });
  }

  watch(theme, (newTheme) => {
    applyTheme(newTheme);
    resolvedTheme.value = newTheme === 'auto' ? getSystemTheme() : newTheme;
  });

  return { theme, setTheme, toggleTheme, resolvedTheme };
}
