import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Read-only star row for a rating value.
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 16, this.color});
  final double rating;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? LizColors.warn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i;
        return Icon(
          half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          size: size,
          color: c,
        );
      }),
    );
  }
}

/// Interactive star input for writing a review.
class RatingInput extends StatelessWidget {
  const RatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = value >= i + 1;
        return IconButton(
          onPressed: () => onChanged(i + 1),
          iconSize: size,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          constraints: const BoxConstraints(),
          icon: Icon(
            filled ? Icons.star : Icons.star_border,
            color: LizColors.warn,
          ),
        );
      }),
    );
  }
}
