import 'package:fan_os/app/router.dart';
import 'package:fan_os/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class FanOsApp extends StatelessWidget {
  const FanOsApp({super.key});

  @override
  Widget build(BuildContext context) {
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
