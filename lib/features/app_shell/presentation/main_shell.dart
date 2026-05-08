import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/presentation/screens/business_dashboard_screen.dart';
import '../../business/presentation/screens/business_onboarding_screen.dart';
import '../../discover/presentation/screens/discover_screen.dart';
import '../../home/presentation/screens/home_screen.dart';
import '../../onboarding/presentation/screens/welcome_screen.dart';
import '../../profile/presentation/screens/profile_screen.dart';
import '../../saved/presentation/screens/saved_screen.dart';
import '../../wallet/presentation/screens/wallet_screen.dart';
import '../../../shared/providers/app_providers.dart';
import 'custom_bottom_nav.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex = widget.initialIndex;
  bool _didRequestLiveLocation = false;
  String? _lastLocationUserId;
  String? _lastCouponRefreshKey;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final authUser = ref.watch(authUserProvider);
    final publicCouponRequestKey = authUser == null
        ? null
        : ref.watch(publicCouponRequestKeyProvider);
    final legacyCouponFallbackActive = ref.watch(
      publicCouponLegacyFallbackActiveProvider,
    );
    final awaitingSessionHydration =
        authUser != null &&
        (!session.isAuthenticated || session.user.id.isEmpty);

    if (_lastLocationUserId != session.user.id) {
      _lastLocationUserId = session.user.id;
      _didRequestLiveLocation = false;
    }

    if (!kIsWeb && session.hasLocationPermission && !_didRequestLiveLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didRequestLiveLocation) {
          return;
        }
        _didRequestLiveLocation = true;
        ref
            .read(sessionControllerProvider.notifier)
            .refreshLocationFromDevice();
      });
    }

    final refreshKey = authUser == null
        ? null
        : '${authUser.uid}|$publicCouponRequestKey';

    if (refreshKey != _lastCouponRefreshKey &&
        authUser != null &&
        session.isAuthenticated &&
        session.user.id.isNotEmpty &&
        !session.isBusinessAccount) {
      _lastCouponRefreshKey = refreshKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref
            .read(publicCouponRefreshControllerProvider.notifier)
            .scheduleRefresh(force: legacyCouponFallbackActive);
      });
    }

    if (awaitingSessionHydration) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 190,
                  child: Image.asset(
                    'assets/branding/spargo_complete_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (session.isBusinessAccount &&
        (session.needsBusinessSetup || !(authUser?.emailVerified ?? false))) {
      return const BusinessOnboardingScreen();
    }

    if (authUser == null && !session.isAuthenticated) {
      return const WelcomeScreen();
    }

    if (session.isBusinessAccount) {
      return const BusinessDashboardScreen();
    }

    final needsUserOnboarding = !session.userOnboardingComplete;
    if (needsUserOnboarding) {
      return const WelcomeScreen();
    }

    final pages = <Widget>[
      const HomeScreen(key: ValueKey<String>('tab-home'), embedded: true),
      const DiscoverScreen(
        key: ValueKey<String>('tab-discover'),
        embedded: true,
      ),
      const SavedScreen(key: ValueKey<String>('tab-saved'), embedded: true),
      const WalletScreen(key: ValueKey<String>('tab-wallet'), embedded: true),
      const ProfileScreen(key: ValueKey<String>('tab-profile'), embedded: true),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
