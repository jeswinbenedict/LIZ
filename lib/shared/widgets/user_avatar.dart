import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/profile.dart';

/// Circular avatar: the person's picture, or their initials on a dark disc
/// ringed in red. One look for everyone — a colour per person made every
/// list a confetti that fought the one red that means something.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, this.radius = 18});
  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(profile.avatarUrl!),
      );
    }
    final p = context.liz;
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surfaceHover,
        shape: BoxShape.circle,
        border: Border.all(
          color: p.accent.withValues(alpha: 0.7),
          width: radius >= 30 ? 2 : 1.2,
        ),
      ),
      child: Text(
        profile.initials,
        style: LizText.headline.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
          height: 1,
        ),
      ),
    );
  }
}
