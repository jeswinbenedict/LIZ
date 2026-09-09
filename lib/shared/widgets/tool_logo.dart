import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/config/env.dart';
import '../models/tool.dart';

/// Square tool logo with a branded gradient + initial fallback when no image.
class ToolLogo extends StatelessWidget {
  const ToolLogo({super.key, required this.tool, this.size = 48});
  final Tool tool;
  final double size;

  static const _gradients = <List<Color>>[
    [Color(0xFF5B5BF5), Color(0xFF8B5CF6)],
    [Color(0xFFFF7A45), Color(0xFFF43F5E)],
    [Color(0xFF12B76A), Color(0xFF0BA5EC)],
    [Color(0xFFEE46BC), Color(0xFF7C3AED)],
    [Color(0xFF0BA5EC), Color(0xFF06B6D4)],
    [Color(0xFFF79009), Color(0xFFEF4444)],
  ];

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    if (tool.logoUrl != null && tool.logoUrl!.isNotEmpty) {
      // Present every logo as a clean, padded "app-icon" tile on a light
      // background so dark, transparent, or oddly-cropped marks all look uniform
      // and professional (instead of a raw edge-to-edge black square). The tile
      // only appears once the image actually loads; otherwise we show the
      // branded initial fallback full-bleed.
      return CachedNetworkImage(
        // A product's own favicon usually sends no CORS header, and Flutter web
        // fetches image bytes — so without the proxy every scraped tool falls
        // back to its initial tile. GitHub avatars happened to work, which is
        // why this only surfaced once the catalog went beyond them.
        imageUrl: Env.proxiedImage(tool.logoUrl!),
        // Decode at the size actually drawn. A grid of tools would otherwise
        // hold full-resolution bitmaps in memory to paint 48-pixel tiles.
        memCacheWidth: (size * 3).round(),
        memCacheHeight: (size * 3).round(),
        imageBuilder: (context, imageProvider) => Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x14000000)),
          ),
          child: Image(image: imageProvider, fit: BoxFit.contain),
        ),
        placeholder: (c, _) => _fallback(radius),
        errorWidget: (c, _, __) => _fallback(radius),
      );
    }
    return _fallback(radius);
  }

  Widget _fallback(double radius) {
    final colors = _gradients[tool.id.hashCode.abs() % _gradients.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        tool.name.isNotEmpty ? tool.name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}
