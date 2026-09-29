import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// First-party usage events: what people view, visit, save and search for.
///
/// This is both Liz's product analytics and the raw material for its ranking.
/// "Rising" counts Liz views, website visits and saves alongside GitHub and
/// Hacker News (migration 0037), so a tool page that is never recorded is a
/// signal lost.
///
/// Privacy by construction: the only identifier is a random id this browser
/// keeps, with no cookies, no third party and no IP address stored. The server
/// (`track()`) drops unknown event names, oversized payloads, repeat views
/// within half an hour, and floods from one address.
///
/// Like the crash reporter, it is fire-and-forget: it never blocks a frame and
/// never throws.
class Analytics {
  Analytics._();

  static const _anonKey = 'liz.anon_id';

  static String? _anonId;
  static String? _lastPath;

  /// Events the server accepts. Anything else is dropped there too; checking
  /// here keeps a typo from failing silently in production.
  static const names = {
    'page_view',
    'tool_view',
    'outbound_click',
    'save',
    'unsave',
    'search',
    'ask',
    'compare',
    'share',
    'sign_up',
    'sign_in',
  };

  /// Loads this browser's id, creating it on first visit.
  static void init(SharedPreferences prefs) {
    var id = prefs.getString(_anonKey);
    if (id == null || !_uuid.hasMatch(id)) {
      id = newAnonId();
      unawaited(prefs.setString(_anonKey, id));
    }
    _anonId = id;
  }

  static String? get anonId => _anonId;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// A version 4 UUID from a secure random source.
  @visibleForTesting
  static String newAnonId([Random? random]) {
    final r = random ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// A screen was shown. Only the path is sent, never the query string, which
  /// can carry what someone typed.
  static void pageView(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    // The router asks on every rebuild of a location, not only on a visit.
    if (path == _lastPath) return;
    _lastPath = path;
    track('page_view', path: path);
  }

  static void track(
    String name, {
    String? toolId,
    String? path,
    Map<String, Object?> props = const {},
  }) {
    assert(names.contains(name), 'Unknown analytics event "$name"');
    if (!Env.useSupabase || _anonId == null) return;
    unawaited(_send(name, toolId, path ?? _lastPath, props));
  }

  static Future<void> _send(
    String name,
    String? toolId,
    String? path,
    Map<String, Object?> props,
  ) async {
    try {
      await Supabase.instance.client.rpc<void>(
        'track',
        params: {
          'p_name': name,
          'p_anon': _anonId,
          'p_tool': toolId,
          'p_path': path,
          'p_props': props,
        },
      );
    } catch (_) {
      // A lost event is not worth an error in front of anyone.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _anonId = null;
    _lastPath = null;
  }
}

/// [text] cut to at most [max] characters, for event properties.
String clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);
