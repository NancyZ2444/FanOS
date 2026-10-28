import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fan_os/app/router.dart';
import 'package:fan_os/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class FanOsApp extends ConsumerWidget {
  const FanOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    api.onAccountBanned = (error) {
      Future.microtask(() {
        if (fanOsRouter.routeInformationProvider.value.uri.path ==
            '/account-banned') {
          return;
        }
        ref.read(sessionProvider.notifier).reset();
        fanOsRouter.go('/account-banned', extra: error);
      });
    };
    return MaterialApp.router(
      title: 'Fan OS',
      debugShowCheckedModeBanner: false,
      theme: FanOsTheme.light,
      routerConfig: fanOsRouter,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
