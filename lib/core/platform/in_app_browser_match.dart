/// Which app's built-in browser [userAgent] belongs to, or null for a real
/// browser. Google blocks its sign-in page in all of these, so the sign-in
/// form says so rather than letting "Continue with Google" fail with Google's
/// own error. Kept apart from the web import so it can be tested.
String? inAppBrowserFromUserAgent(String userAgent) {
  const apps = <String, String>{
    'LinkedInApp': 'LinkedIn',
    'Instagram': 'Instagram',
    'FBAN': 'Facebook',
    'FBAV': 'Facebook',
    'FB_IAB': 'Facebook',
    'Snapchat': 'Snapchat',
    'MicroMessenger': 'WeChat',
    'Line/': 'LINE',
    'Twitter': 'X',
  };
  for (final entry in apps.entries) {
    if (userAgent.contains(entry.key)) return entry.value;
  }
  // Any other Android WebView: an app showing the page, not a browser.
  if (userAgent.contains('; wv)')) return 'this app';
  return null;
}
