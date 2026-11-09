import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/system_ui.dart';
import '../browser/detected_media.dart';

/// 全屏 Media3 ExoPlayer 页面：播放浏览器里检测到的视频地址。
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({super.key, required this.media});

  final DetectedMedia media;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  @override
  void initState() {
    super.initState();
    enterFullscreen();
  }

  @override
  void dispose() {
    exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: AndroidView(
              viewType: 'readlater/media3',
              creationParams: {
                'url': widget.media.url,
                'referer': widget.media.sourcePage,
                'userAgent': widget.media.userAgent,
                'title': widget.media.title,
              },
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
