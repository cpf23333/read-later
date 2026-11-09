import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models/site.dart';
import '../../core/util/origin.dart';

/// 站点卡片：图标 + 名称 + host。
class SiteCard extends StatelessWidget {
  const SiteCard({super.key, required this.site, required this.onTap, this.onLongPress});

  final Site site;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final host = hostOf(site.url) ?? site.url;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _SiteIcon(iconUrl: site.iconUrl, host: host),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.title.isEmpty ? host : site.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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
}

class _SiteIcon extends StatelessWidget {
  const _SiteIcon({this.iconUrl, required this.host});

  final String? iconUrl;
  final String host;

  @override
  Widget build(BuildContext context) {
    final url = iconUrl;
    if (url != null && url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorWidget: (context, imageUrl, error) => _letterAvatar(context),
        ),
      );
    }
    return _letterAvatar(context);
  }

  Widget _letterAvatar(BuildContext context) {
    final letter = host.isEmpty ? '?' : host.substring(0, 1).toUpperCase();
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(letter, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
