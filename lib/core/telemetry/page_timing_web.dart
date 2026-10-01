import 'package:web/web.dart' as web;

/// performance.now() counts from the start of navigation, so at the first
/// frame it is how long a visitor waited to see anything from the app.
double? millisSinceNavigation() => web.window.performance.now();
