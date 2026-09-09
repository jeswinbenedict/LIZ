import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps an auto-disposing provider alive for a while after the last widget
/// stops watching it.
///
/// Plain `autoDispose` throws the result away the instant a screen leaves, so
/// tapping back onto a feed you were just looking at refetches it and shows a
/// loading state for something that was on screen a second ago. Never
/// disposing has the opposite problem: every category, sort and search term
/// visited in a session stays in memory for the rest of it.
///
/// A short grace period gets both — instant back-navigation, and memory that
/// settles rather than climbs.
void cacheFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  Timer? timer;

  ref.onDispose(() => timer?.cancel());
  // Nothing is watching any more: start the clock.
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(duration, link.close);
  });
  // Something started watching again before the clock ran out.
  ref.onResume(() {
    timer?.cancel();
    timer = null;
  });
}
