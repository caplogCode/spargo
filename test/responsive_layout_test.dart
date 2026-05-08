import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spargo/core/widgets/immersive_cover.dart';
import 'package:spargo/data/mock/mock_businesses.dart';
import 'package:spargo/data/mock/mock_deals.dart';
import 'package:spargo/features/app_shell/presentation/main_shell.dart';
import 'package:spargo/features/app_shell/presentation/custom_bottom_nav.dart';
import 'package:spargo/features/auth/presentation/screens/register_screen.dart';
import 'package:spargo/features/auth/presentation/screens/login_screen.dart';
import 'package:spargo/features/business/presentation/screens/business_onboarding_screen.dart';
import 'package:spargo/features/deals/presentation/screens/deal_detail_screen.dart';
import 'package:spargo/features/discover/presentation/screens/discover_screen.dart';
import 'package:spargo/features/home/presentation/screens/home_screen.dart';
import 'package:spargo/features/onboarding/presentation/screens/location_permission_screen.dart';
import 'package:spargo/features/onboarding/presentation/screens/interests_screen.dart';
import 'package:spargo/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:spargo/features/saved/presentation/screens/saved_screen.dart';
import 'package:spargo/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:spargo/routing/app_routes.dart';
import 'package:spargo/shared/widgets/hero_deal_card.dart';
import 'package:spargo/theme/app_theme.dart';

void main() {
  Future<void> pumpResponsivePage(
    WidgetTester tester, {
    required Widget child,
    required Size size,
    bool withProviders = false,
    double devicePixelRatio = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final widget = MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: withProviders ? ProviderScope(child: child) : child,
    );

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('welcome screen stays stable on short viewport', (tester) async {
    await pumpResponsivePage(
      tester,
      child: const WelcomeScreen(),
      size: const Size(360, 440),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Loslegen'), findsOneWidget);
  });

  testWidgets('welcome screen continues to interests flow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const WelcomeScreen(),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.interests) {
            return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('Interests target'))),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Loslegen'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Interests target'), findsOneWidget);
  });

  testWidgets('location permission screen stays stable on short viewport', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const LocationPermissionScreen(),
      size: const Size(360, 440),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Standort freigeben'), findsOneWidget);
  });

  testWidgets('interests screen stays stable on mobile viewport', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const InterestsScreen(),
      size: const Size(390, 844),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Interessen speichern'), findsOneWidget);
  });

  testWidgets('deal detail CTA stays stable on narrow viewport', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const DealDetailScreen(dealId: 'deal_ember_duo'),
      size: const Size(320, 740),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Jetzt aktivieren'), findsOneWidget);
  });

  testWidgets('deal detail stays stable on fractional pixel ratio', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const DealDetailScreen(dealId: 'deal_ember_duo'),
      size: const Size(320, 740),
      withProviders: true,
      devicePixelRatio: 1.3,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('login screen stays stable with keyboard-sized height', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const LoginScreen(),
      size: const Size(360, 520),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Einloggen'), findsWidgets);
  });

  testWidgets('register screen stays stable with keyboard-sized height', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const RegisterScreen(),
      size: const Size(360, 520),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Konto erstellen'), findsOneWidget);
  });

  testWidgets('business onboarding stays stable on compact viewport', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const BusinessOnboardingScreen(),
      size: const Size(360, 520),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Merchant Tools aktivieren'), findsOneWidget);
  });

  testWidgets('immersive cover stays stable on compact card footprint', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 116,
            child: ImmersiveCover(
              palette: const <int>[0xFF1B1820, 0xFFE46952, 0xFFF2B441],
              title: '35%',
              subtitle: 'Studio Nord',
              icon: Icons.local_fire_department_rounded,
              height: 126,
            ),
          ),
        ),
      ),
      size: const Size(320, 320),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('35%'), findsOneWidget);
  });

  testWidgets('immersive cover stays stable on wide slim footprint', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 328,
            child: ImmersiveCover(
              palette: const <int>[0xFF9D5A3E, 0xFFB86A45, 0xFFCC7C56],
              title: 'Weekend Run',
              subtitle: 'Nordmarkt',
              badge: '34% Vorteil',
              icon: Icons.bookmark_border_rounded,
              height: 82,
            ),
          ),
        ),
      ),
      size: const Size(360, 240),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('immersive cover stays stable on medium low-height footprint', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 212,
            child: ImmersiveCover(
              palette: const <int>[0xFF8E533B, 0xFFB66D49, 0xFFD79F73],
              title: 'Sharing Brunch Board',
              subtitle: 'Pflastergold Bistro',
              badge: '34% Vorteil',
              icon: Icons.restaurant_rounded,
              height: 108,
            ),
          ),
        ),
      ),
      size: const Size(320, 240),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav stays stable on narrow mobile width', (tester) async {
    await pumpResponsivePage(
      tester,
      child: Scaffold(
        bottomNavigationBar: CustomBottomNav(currentIndex: 2, onTap: (_) {}),
      ),
      size: const Size(318, 140),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Merken'), findsOneWidget);
  });

  testWidgets('bottom nav stays stable on fractional pixel ratio', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: Scaffold(
        bottomNavigationBar: CustomBottomNav(currentIndex: 2, onTap: (_) {}),
      ),
      size: const Size(318, 140),
      devicePixelRatio: 1.3,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('discover screen stays stable embedded', (tester) async {
    await pumpResponsivePage(
      tester,
      child: const DiscoverScreen(embedded: true),
      size: const Size(390, 844),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Entdecken'), findsWidgets);
  });

  testWidgets('home screen stays stable embedded', (tester) async {
    await pumpResponsivePage(
      tester,
      child: const HomeScreen(embedded: true),
      size: const Size(390, 844),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Dein Gutscheinheft'), findsWidgets);
  });

  testWidgets('hero deal card stays stable on compact footprint', (
    tester,
  ) async {
    final deal = mockDeals.first;
    final business = mockBusinesses.firstWhere(
      (item) => item.id == deal.businessId,
    );

    await pumpResponsivePage(
      tester,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 392,
            child: HeroDealCard(deal: deal, business: business, onTap: () {}),
          ),
        ),
      ),
      size: const Size(360, 720),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen stays stable after scrolling to coupon rails', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const HomeScreen(embedded: true),
      size: const Size(390, 720),
      withProviders: true,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -540));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Coupon Typen'), findsWidgets);
  });

  testWidgets('saved screen stays stable embedded', (tester) async {
    await pumpResponsivePage(
      tester,
      child: const SavedScreen(embedded: true),
      size: const Size(390, 844),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Merken'), findsWidgets);
  });

  testWidgets('wallet screen stays stable embedded', (tester) async {
    await pumpResponsivePage(
      tester,
      child: const WalletScreen(embedded: true),
      size: const Size(390, 844),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Wallet'), findsWidgets);
  });

  testWidgets('main shell navigates to discover and saved without crashing', (
    tester,
  ) async {
    await pumpResponsivePage(
      tester,
      child: const MainShell(),
      size: const Size(390, 844),
      withProviders: true,
    );

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Nah'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Entdecken'), findsWidgets);

    await tester.tap(find.text('Merken'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Merken'), findsWidgets);
  });
}
