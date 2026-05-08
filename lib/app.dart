import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_routes.dart';
import 'routing/app_router.dart';
import 'shared/i18n/app_translation_controller.dart';
import 'shared/providers/app_language_provider.dart';
import 'shared/widgets/auto_translate_text.dart' show AppTranslationScope;
import 'theme/app_theme.dart';

class SpargoApp extends ConsumerWidget {
  const SpargoApp({super.key});

  String _normalizeInitialRoute(String initialRoute) {
    final rawRoute = initialRoute.trim();
    if (rawRoute.isEmpty || rawRoute == '/') {
      return AppRoutes.splash;
    }

    final uri = Uri.tryParse(rawRoute);
    final fragment = uri?.fragment.trim() ?? '';
    if (fragment.startsWith('/')) {
      return fragment;
    }

    final path = uri?.path.trim() ?? rawRoute;
    if (path.isEmpty || path == '/') {
      return AppRoutes.splash;
    }
    return path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageControllerProvider);
    final translations = ref.watch(
      appTranslationControllerProvider.select((state) => state.translations),
    );

    return MaterialApp(
      title: 'sparGO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      locale: language.locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) {
        return AppTranslationScope(
          languageCode: language.languageCode,
          translationsIdentity: translations,
          child: child ?? const SizedBox.shrink(),
        );
      },
      onGenerateInitialRoutes: (initialRoute) {
        final normalizedRoute = _normalizeInitialRoute(initialRoute);
        return <Route<dynamic>>[
          AppRouter.onGenerateRoute(RouteSettings(name: normalizedRoute)),
        ];
      },
      onGenerateRoute: AppRouter.onGenerateRoute,
      onUnknownRoute: (settings) => AppRouter.onGenerateRoute(
        const RouteSettings(name: AppRoutes.splash),
      ),
    );
  }
}
