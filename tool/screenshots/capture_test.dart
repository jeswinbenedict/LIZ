// Renders every main screen to PNG, through the app's real router and shell,
// with the real fonts, at a phone and a desktop size.
//
//   flutter test tool/screenshots/capture_test.dart --dart-define=SHOT=after
//
// Images land in build/screens/<SHOT>/. Not part of `flutter test`: it lives
// outside test/ because it writes files and exists to be looked at, not to
// pass or fail. It is how the redesign was judged screen by screen.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/auth_gate.dart';
import 'package:liz/app/router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';

const _shot = String.fromEnvironment('SHOT', defaultValue: 'current');

const _screens = <String, String>{
  'discover': '/',
  'search': '/search?q=video',
  'ask': '/ask',
  'tool': '/tool/t-1',
  'compare': '/compare?ids=t-1,t-2,t-3',
  'news': '/news',
  'saved': '/saved',
  'alerts': '/alerts',
  'profile': '/profile',
  'settings': '/profile/settings',
  'notfound': '/no-such-page',
  'signin': '/signin',
};

const _sizes = <String, Size>{
  'phone': Size(390, 844),
  'desktop': Size(1440, 900),
};

Future<void> _loadFonts() async {
  for (final (family, file) in [
    ('SpaceGrotesk', 'SpaceGrotesk-Latin.ttf'),
    ('JetBrainsMono', 'JetBrainsMono-Latin.ttf'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file'))).load();
  }
  // Material icons from the SDK, so icons draw as icons rather than boxes.
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  {
    for (final size in _sizes.entries) {
      for (final screen in _screens.entries) {
        final name = '${screen.key}-${size.key}';
        testWidgets(name, (tester) async {
          tester.view.physicalSize = size.value * 2;
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);

          final container = ProviderContainer();
          await tester.runAsync(() async {
            await container.read(authRepositoryProvider).signInAsDemo();
            final track = container.read(trackRepositoryProvider);
            for (final id in ['t-1', 't-2', 't-4']) {
              await track.toggleBookmark(id);
            }
          });

          final gate = AuthGate(container.read(authRepositoryProvider));
          addTearDown(gate.dispose);
          await tester.runAsync(
            () => container.read(authRepositoryProvider).restored,
          );
          final router = buildRouter(gate);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: UncontrolledProviderScope(
                container: container,
                child: MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  theme: LizTheme.app(),
                  routerConfig: router,
                ),
              ),
            ),
          );
          router.go(screen.value);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Asset images decode off the fake clock; give them real time.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 400)),
          );
          await tester.pumpAndSettle();

          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/screens/$_shot/$name.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
          });

          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
        });
      }
    }
  }
}
