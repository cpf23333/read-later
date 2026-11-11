import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart'
    hide enterFullscreen, exitFullscreen;

import '../../platform/system_ui.dart';
import '../browser/detected_media.dart';
import 'dash_manifest.dart';
import 'header_media_proxy.dart';

/// 全屏 media_kit 播放页：播放浏览器里检测到的视频地址。
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({super.key, required this.media});

  final DetectedMedia media;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  File? _manifestFile;
  HeaderMediaProxy? _mediaProxy;
  String? _error;

  @override
  void initState() {
    super.initState();
    enterFullscreen();

    _player = Player();
    _controller = VideoController(_player);
    _errorSubscription = _player.stream.error.listen((message) {
      if (!mounted) return;
      setState(() => _error = message);
    });
    unawaited(_openMedia());
  }

  Future<void> _openMedia() async {
    var url = widget.media.url;
    final headers = <String, String>{
      if (widget.media.userAgent.trim().isNotEmpty)
        'User-Agent': widget.media.userAgent,
      if (widget.media.sourcePage.trim().isNotEmpty)
        'Referer': widget.media.sourcePage,
      if (widget.media.cookie.trim().isNotEmpty) 'Cookie': widget.media.cookie,
    };

    try {
      final dash = widget.media.dash;
      if (dash != null) {
        _mediaProxy = await HeaderMediaProxy.start(
          headers,
          allowedHosts: dash.allowedHosts,
        );
        final manifest = buildDashManifest(
          dash,
          rewriteBaseUrl: _mediaProxy!.rewrite,
        );
        final file = File(
          '${Directory.systemTemp.path}/readlater_dash_'
          '${DateTime.now().microsecondsSinceEpoch}.mpd',
        );
        await file.writeAsString(manifest);
        _manifestFile = file;
        url = file.path;
      }
      if (!mounted) return;
      await _player.open(Media(url, httpHeaders: headers), play: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _player.dispose();
    final file = _manifestFile;
    if (file != null) {
      unawaited(file.delete().catchError((_) => file));
    }
    unawaited(_mediaProxy?.close());
    exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Video(controller: _controller)),
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      '播放失败：$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
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
