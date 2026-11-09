import 'dart:convert';

/// 把截图字节转为服务器可识别的 data URL（服务器按 data:image/* 保存原图）。
String imageDataUrl(List<int> bytes, {String mimeType = 'image/jpeg'}) {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}
