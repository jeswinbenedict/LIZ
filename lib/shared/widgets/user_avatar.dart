import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/profile.dart';

/// Circular avatar with a deterministic color + initials fallback.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, this.radius = 18});
  final Profile profile;
  final double radius;

  Color _color() {
    final palette = [
      const Color(0xFF5B5BF5),
      const Color(0xFFFF7A45),
      const Color(0xFF12B76A),
      const Color(0xFFEE46BC),
      const Color(0xFF0BA5EC),
      const Color(0xFFF79009),
    ];
    return palette[profile.id.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(profile.avatarUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      // White initials on the palette's lighter members (green, amber, cyan)
      // measured as low as 2.4:1; darken each just enough to read.
      backgroundColor: LizColors.legibleOn(_color(), Colors.white),
      child: Text(
        profile.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
