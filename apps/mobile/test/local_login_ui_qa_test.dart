// Opt-in visual QA of the production LoginPage, not a replacement mockup.
// No network, account access, simulator control, login or SMS request is used.
// Run from apps/mobile:
// flutter test test/local_login_ui_qa_test.dart --no-pub \
//   --dart-define=LOCAL_LOGIN_UI_QA=true --reporter expanded
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryAuthApi extends ApiClient {
  final reads = <String>[];

  @override
  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    reads.add(path);
    if (path != '/auth/capabilities') {
      throw StateError('Visual QA must not read accounts: $path');
    }
    return {
      for (final provider in authProviders) '${provider}_available': false,
    };
  }

  @override
  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    bool authenticated = true,
    String? idempotencyKey,
  }) async => throw StateError('Visual QA must not send a request: $path');
}

ThemeData _qaTheme() {
  final theme = FanOsTheme.light;
  ButtonStyle font(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(
          (style?.textStyle?.resolve({}) ?? const TextStyle()).copyWith(
            fontFamily: 'FanQa',
          ),
        ),
      );
  // Only the screenshot harness substitutes a local font. ButtonTheme styles
  // must be covered explicitly, since they do not inherit the body font.
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'FanQa'),
    filledButtonTheme: FilledButtonThemeData(
      style: font(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: font(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: font(theme.textButtonTheme.style),
    ),
  );
}

Future<void> _loadLocalFontsAndHero() async {
  const fontPath = String.fromEnvironment(
    'LOCAL_LOGIN_QA_FONT',
    defaultValue: '/System/Library/Fonts/STHeiti Light.ttc',
  );
  final fontFile = File(fontPath);
  if (!fontFile.existsSync()) {
    throw StateError(
      'Provide a local Chinese font with --dart-define=LOCAL_LOGIN_QA_FONT=...',
    );
  }
  final font = ByteData.sublistView(await fontFile.readAsBytes());
  // Flutter tests otherwise render Ahem blocks. Register local Chinese-capable
  // faces under platform fallback families without altering production theme.
  for (final family in [
    'FanQa',
    'Ahem',
    'Roboto',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Helvetica Neue',
    '.SF UI Text',
    '.SF UI Display',
  ]) {
    await (FontLoader(family)..addFont(Future.value(font))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

  // Decode the actual generated asset before fake-clock widget frames begin;
  // a fallback blank box must not silently pass this visual QA.
  const provider = AssetImage('assets/auth/login-hero.png');
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final asset = await rootBundle.load(key.name);
  final codec = await ui.instantiateImageCodec(
    asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
  );
  final frame = await codec.getNextFrame();
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: frame.image)),
    ),
  );
  codec.dispose();
}

void main() {
  testWidgets(
    '390x844 actual login and phone pages, unchecked and checked consent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final output = Directory('../../output/catalog-feedback-20261028')
            .absolute;
        await tester.runAsync(() async {
          await output.create(recursive: true);
          await _loadLocalFontsAndHero();
        });
        final api = _MemoryAuthApi();
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _qaTheme(),
                home: const LoginPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        void checkConsent(bool checked) {
          final checkbox = find.byKey(const Key('login-consent'));
          expect(tester.widget<Checkbox>(checkbox).value, checked);
          expect(
            tester.getCenter(checkbox).dy,
            closeTo(
              tester.getCenter(find.byKey(const Key('login-consent-text'))).dy,
              1,
            ),
          );
          expect(
            tester.getCenter(find.byKey(const Key('login-consent-group'))).dx,
            closeTo(195, 1),
          );
          expect(tester.takeException(), isNull);
        }

        Future<void> capture(String name, {required bool checked}) async {
          await tester.pumpAndSettle();
          // These two production buttons have local TextStyles that override
          // ButtonTheme entirely. In flutter_tester an unspecified family uses
          // Ahem rather than platform CJK fallback. Substitute only the font of
          // their real rendered labels; keep content, size, weight and controls.
          for (final label in ['用户协议', '隐私政策']) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(label),
            );
            final original = paragraph.text;
            expect(original.toPlainText(), label);
            paragraph.text = TextSpan(
              text: original.toPlainText(),
              style: (original.style ?? const TextStyle()).copyWith(
                fontFamily: 'FanQa',
              ),
            );
          }
          await tester.pump();
          checkConsent(checked);
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              expect(image.width, 780);
              expect(image.height, 1688);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('${output.path}/$name.png').writeAsBytes(
                png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
              );
            } finally {
              image.dispose();
            }
          });
          debugPrint('Login UI QA: ${output.path}/$name.png');
        }

        expect(find.byKey(const Key('login-phone')), findsNothing);
        final hero = find.descendant(
          of: find.byKey(const Key('login-hero')),
          matching: find.byType(RawImage),
        );
        expect(hero, findsOneWidget);
        expect(tester.widget<RawImage>(hero).image, isNotNull);
        for (final provider in authProviders) {
          expect(
            tester
                .widget<IconButton>(find.byKey(Key('login-provider-$provider')))
                .onPressed,
            isNull,
          );
        }
        await capture('login-choice-unchecked-390', checked: false);
        await tester.tap(find.byKey(const Key('login-consent')));
        await capture('login-choice-checked-390', checked: true);

        await tester.tap(find.byKey(const Key('login-open-phone')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('login-phone')), findsOneWidget);
        expect(find.byKey(const Key('login-password')), findsNothing);
        await capture('login-phone-checked-390', checked: true);
        await tester.tap(find.byKey(const Key('login-consent')));
        await capture('login-phone-unchecked-390', checked: false);

        expect(api.reads, ['/auth/capabilities']);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        // Painting invariants are checked before registered tearDown callbacks.
        debugDisableShadows = oldShadows;
      }
    },
    skip: !const bool.fromEnvironment('LOCAL_LOGIN_UI_QA'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
