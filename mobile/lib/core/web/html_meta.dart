import 'package:html/parser.dart' as html_parser;

/// 从 HTML 解析标题：og:title 优先，其次 <title>。
String? parseTitle(String html) {
  final document = html_parser.parse(html);

  final ogTitle = document
      .querySelector('meta[property="og:title"]')
      ?.attributes['content']
      ?.trim();
  if (ogTitle != null && ogTitle.isNotEmpty) return ogTitle;

  final title = document.querySelector('title')?.text.trim();
  return (title == null || title.isEmpty) ? null : title;
}

/// 从 HTML 解析 favicon 地址，并把相对路径解析为绝对 URL。
String? parseIconUrl(String html, Uri pageUrl) {
  final document = html_parser.parse(html);

  final link = document.querySelector('link[rel~="icon"]') ??
      document.querySelector('link[rel="shortcut icon"]');
  final href = link?.attributes['href']?.trim();
  if (href == null || href.isEmpty) return null;

  return pageUrl.resolve(href).toString();
}
