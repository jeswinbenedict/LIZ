import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../models/tool.dart';

/// Square tool logo with a branded gradient + initial fallback when no image.
class ToolLogo extends StatelessWidget {
  const ToolLogo({super.key, required this.tool, this.size = 48});
  final Tool tool;
  final double size;

  // Hues for tools without a logo. Shown as a soft tint with a coloured
  // initial rather than a saturated gradient, which used to be the loudest
  // thing on a grid and pulled the eye away from the tools that had logos.
  static const _hues = <Color>[
    Color(0xFF5856D6),
    Color(0xFFFF6B35),
    Color(0xFF28A745),
    Color(0xFFD63384),
    Color(0xFF0A84FF),
    Color(0xFFB8860B),
  ];

  /// App-icon squircle: 22.5% of the side, like the icons it stands for.
  ShapeBorder _shape(BuildContext context, {bool outlined = true}) =>
      RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(size * 0.225),
        side: outlined
            ? BorderSide(color: context.liz.hairline)
            : BorderSide.none,
      );

  @override
  Widget build(BuildContext context) {
    // The card repeats the name in text beside this, so announcing the logo
    // too would read it twice. Marking it decorative keeps a screen reader on
    // the content rather than on the picture of it.
    return ExcludeSemantics(child: _buildMark(context));
  }

  Widget _buildMark(BuildContext context) {
    final stored = tool.logoUrl != null && tool.logoUrl!.isNotEmpty;
    // A tenth of the catalog was scraped without a logo, and every one showed
    // a letter tile even when its site has a perfectly good icon. Asking the
    // proxy by domain finds it; a miss still falls back to the letter.
    final source = stored
        ? Env.proxiedImage(tool.logoUrl!, fallbackDomain: tool.websiteUrl)
        : Env.domainLogo(tool.websiteUrl);
    if (source != null) {
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
        imageUrl: source,
        // Decode at the size actually drawn. A grid of tools would otherwise
        // hold full-resolution bitmaps in memory to paint 48-pixel tiles.
        memCacheWidth: (size * 3).round(),
        memCacheHeight: (size * 3).round(),
        // Marks are drawn on white in both themes: most logos are made for a
        // light background, and a dark tile would swallow the dark ones.
        imageBuilder: (context, imageProvider) => Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.14),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: _shape(context),
          ),
          child: Image(image: imageProvider, fit: BoxFit.contain),
        ),
        placeholder: (c, _) => _fallback(c),
        errorWidget: (c, _, _) => _fallback(c),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final p = context.liz;
    final hue = _hues[tool.id.hashCode.abs() % _hues.length];
    final tile = Color.alphaBlend(hue.withValues(alpha: 0.14), p.surface);
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(color: tile, shape: _shape(context)),
      alignment: Alignment.center,
      child: Text(
        tool.name.isNotEmpty ? tool.name[0].toUpperCase() : '?',
        style: LizText.title2.copyWith(
          color: LizColors.legibleOn(hue, tile, minimum: 3),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          height: 1,
        ),
      ),
    );
  }
}
