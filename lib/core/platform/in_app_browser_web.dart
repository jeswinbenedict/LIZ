import 'package:web/web.dart' as web;

import 'in_app_browser_match.dart';

String? inAppBrowserName() =>
    inAppBrowserFromUserAgent(web.window.navigator.userAgent);
