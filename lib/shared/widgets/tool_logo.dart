import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: tool.logoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (c, _) => _fallback(radius),
          errorWidget: (c, _, __) => _fallback(radius),
        ),
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
