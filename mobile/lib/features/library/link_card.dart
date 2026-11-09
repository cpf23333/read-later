import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/link.dart';
import '../../core/util/origin.dart';

/// 收藏卡片（网格/列表共用）。
class LinkCard extends StatelessWidget {
  const LinkCard({
    super.key,
    required this.link,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final LinkItem link;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final image = link.nearbyImage ?? link.screenshot;
    final title = link.title.trim();
    final hasTitle = title.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 64, height: 64, child: _Thumb(image: image)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: link.url,
                      child: Text(
                        hasTitle ? title : link.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (hasTitle) ...[
                      const SizedBox(height: 4),
                      Text(
                        hostOf(link.url) ?? link.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(link.createdAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(int millis) {
    if (millis <= 0) return '';
    return DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(millis));
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.image});

  final String? image;

  @override
  Widget build(BuildContext context) {
    final value = image;
    if (value == null || value.isEmpty) {
      return _placeholder(context);
    }

    if (value.startsWith('data:')) {
      try {
        return Image.memory(base64Decode(value.split(',').last), fit: BoxFit.cover);
      } catch (_) {
        return _placeholder(context);
      }
    }

    return CachedNetworkImage(
      imageUrl: value,
      fit: BoxFit.cover,
      placeholder: (context, url) => _placeholder(context),
      errorWidget: (context, url, error) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.outline),
    );
  }
}
