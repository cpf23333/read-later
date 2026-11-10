import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user_agent_rule.dart';
import '../../core/models/site.dart';
import '../../providers.dart';
import 'user_agent.dart';

/// 全局默认 User-Agent 状态。
class GlobalUserAgentState {
  final UserAgentRule rule;
  final bool loading;
  final bool initialized;
  final String? error;

  const GlobalUserAgentState({
    this.rule = const UserAgentRule(),
    this.loading = false,
    this.initialized = false,
    this.error,
  });

  GlobalUserAgentState copyWith({
    UserAgentRule? rule,
    bool? loading,
    bool? initialized,
    String? error,
    bool clearError = false,
  }) {
    return GlobalUserAgentState(
      rule: rule ?? this.rule,
      loading: loading ?? this.loading,
      initialized: initialized ?? this.initialized,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GlobalUserAgentController extends Notifier<GlobalUserAgentState> {
  @override
  GlobalUserAgentState build() => const GlobalUserAgentState();

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rule = await ref.read(apiClientProvider).getDefaultUserAgent();
      state = state.copyWith(
        rule: rule,
        loading: false,
        initialized: true,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        initialized: true,
        error: '$error',
      );
    }
  }

  Future<void> save(UserAgentRule rule) async {
    final saved = await ref
        .read(apiClientProvider)
        .updateDefaultUserAgent(
          mode: rule.mode,
          userAgent: rule.customUserAgent,
        );
    state = state.copyWith(
      rule: saved,
      loading: false,
      initialized: true,
      clearError: true,
    );
  }
}

/// 站点列表 + 全局默认 UA 的解析辅助。
String? resolveUserAgentForUrl(
  String url,
  List<Site> sites,
  UserAgentRule globalRule,
) {
  final host = _hostKey(url);
  if (host == null) return userAgentForRule(globalRule);

  for (final site in sites) {
    if (_hostKey(site.url) != host) continue;
    if (site.userAgentMode == 'desktop') return desktopUserAgent;
    if (site.userAgentMode == 'custom') {
      final custom = site.userAgent?.trim() ?? '';
      return custom.isEmpty ? userAgentForRule(globalRule) : custom;
    }
    return userAgentForRule(globalRule);
  }
  return userAgentForRule(globalRule);
}

String? _hostKey(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}
