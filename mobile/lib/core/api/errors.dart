/// API 错误类型（统一映射为可展示文案）。
sealed class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

/// 服务器未配置。
class NotConfiguredException extends ApiException {
  const NotConfiguredException([super.message = '服务器未配置']);
}

/// 网络错误（超时、连接失败）。
class NetworkException extends ApiException {
  const NetworkException([super.message = '网络连接失败']);
}

/// 鉴权失败（401）。
class AuthException extends ApiException {
  const AuthException([super.message = 'API Key 无效']);
}

/// 请求参数错误（400）。
class ValidationException extends ApiException {
  const ValidationException([super.message = '请求参数错误']);
}

/// 服务器错误（5xx）。
class ServerException extends ApiException {
  const ServerException([super.message = '服务器错误']);
}
