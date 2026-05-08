import 'package:flutter/material.dart';
import '../domain/models/deal_models.dart';
import '../features/app_shell/presentation/main_shell.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/business/presentation/screens/business_analytics_screen.dart';
import '../features/business/presentation/screens/business_branches_screen.dart';
import '../features/business/presentation/screens/business_dashboard_screen.dart';
import '../features/business/presentation/screens/business_deal_editor_screen.dart';
import '../features/business/presentation/screens/business_deals_screen.dart';
import '../features/business/presentation/screens/business_onboarding_screen.dart';
import '../features/business/presentation/screens/business_profile_screen.dart';
import '../features/business/presentation/screens/business_register_screen.dart';
import '../features/business/presentation/screens/business_redemptions_screen.dart';
import '../features/business/presentation/screens/business_stories_screen.dart';
import '../features/business/presentation/screens/create_story_screen.dart';
import '../features/business/presentation/screens/manage_business_profile_screen.dart';
import '../features/deals/presentation/screens/deal_detail_screen.dart';
import '../features/discover/presentation/screens/discover_screen.dart';
import '../features/legal/presentation/screens/legal_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/onboarding/presentation/screens/interests_screen.dart';
import '../features/onboarding/presentation/screens/location_permission_screen.dart';
import '../features/onboarding/presentation/screens/splash_screen.dart';
import '../features/onboarding/presentation/screens/welcome_screen.dart';
import '../features/profile/presentation/screens/edit_profile_screen.dart';
import '../features/profile/presentation/screens/invite_friends_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/profile/presentation/screens/rewards_screen.dart';
import '../features/profile/presentation/screens/settings_screen.dart';
import '../features/saved/presentation/screens/saved_screen.dart';
import '../features/search/presentation/screens/categories_screen.dart';
import '../features/search/presentation/screens/category_feed_screen.dart';
import '../features/search/presentation/screens/search_results_screen.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/stories/presentation/screens/story_viewer_screen.dart';
import '../features/wallet/presentation/screens/wallet_screen.dart';
import 'app_routes.dart';
import 'transitions.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return buildAppRoute(settings: settings, page: const SplashScreen());
      case AppRoutes.welcome:
        final args = settings.arguments;
        final welcomeArgs = args is WelcomeArgs
            ? args
            : args is int
            ? WelcomeArgs(initialStep: args)
            : const WelcomeArgs();
        return buildAppRoute(
          settings: settings,
          page: WelcomeScreen(initialStep: welcomeArgs.initialStep),
        );
      case AppRoutes.interests:
        return buildAppRoute(settings: settings, page: const InterestsScreen());
      case AppRoutes.locationPermission:
        return buildAppRoute(
          settings: settings,
          page: const LocationPermissionScreen(),
        );
      case AppRoutes.login:
        return buildAppRoute(
          settings: settings,
          page: const LoginScreen(initialMode: LoginScreenMode.login),
        );
      case AppRoutes.register:
        return buildAppRoute(settings: settings, page: const RegisterScreen());
      case AppRoutes.businessRegister:
        return buildAppRoute(
          settings: settings,
          page: const BusinessRegisterScreen(),
        );
      case AppRoutes.shell:
        final args = (settings.arguments as ShellArgs?) ?? const ShellArgs();
        return buildAppRoute(
          settings: settings,
          page: MainShell(initialIndex: args.initialIndex),
        );
      case AppRoutes.storyViewer:
        final args = _storyViewerArgs(settings);
        if (args == null) {
          return _fallbackToShell(settings);
        }
        return buildAppRoute(
          settings: settings,
          page: StoryViewerScreen(
            storyId: args.storyId,
            initialItemIndex: args.initialItemIndex,
          ),
        );
      case AppRoutes.search:
        return buildAppRoute(settings: settings, page: const SearchScreen());
      case AppRoutes.searchResults:
        final args = _searchResultsArgs(settings);
        if (args == null) {
          return buildAppRoute(settings: settings, page: const SearchScreen());
        }
        return buildAppRoute(
          settings: settings,
          page: SearchResultsScreen(initialQuery: args.query),
        );
      case AppRoutes.categories:
        return buildAppRoute(
          settings: settings,
          page: const CategoriesScreen(),
        );
      case AppRoutes.categoryFeed:
        final args = _categoryFeedArgs(settings);
        if (args == null) {
          return buildAppRoute(
            settings: settings,
            page: const CategoriesScreen(),
          );
        }
        return buildAppRoute(
          settings: settings,
          page: CategoryFeedScreen(category: args.category),
        );
      case AppRoutes.discover:
        return buildAppRoute(settings: settings, page: const DiscoverScreen());
      case AppRoutes.dealDetail:
        final args = _dealRouteArgs(settings);
        if (args == null) {
          return _fallbackToShell(settings);
        }
        return buildAppRoute(
          settings: settings,
          page: DealDetailScreen(dealId: args.dealId),
        );
      case AppRoutes.businessProfile:
        final args = _businessRouteArgs(settings);
        if (args == null) {
          return _fallbackToShell(settings);
        }
        return buildAppRoute(
          settings: settings,
          page: BusinessProfileScreen(businessId: args.businessId),
        );
      case AppRoutes.saved:
        return buildAppRoute(settings: settings, page: const SavedScreen());
      case AppRoutes.activeDeals:
      case AppRoutes.wallet:
        final args = (settings.arguments as WalletArgs?) ?? const WalletArgs();
        return buildAppRoute(
          settings: settings,
          page: WalletScreen(initialTab: args.initialTab),
        );
      case AppRoutes.notifications:
        return buildAppRoute(
          settings: settings,
          page: const NotificationsScreen(),
        );
      case AppRoutes.profile:
        return buildAppRoute(settings: settings, page: const ProfileScreen());
      case AppRoutes.settings:
        return buildAppRoute(settings: settings, page: const SettingsScreen());
      case AppRoutes.legal:
        return buildAppRoute(settings: settings, page: const LegalScreen());
      case AppRoutes.editProfile:
        return buildAppRoute(
          settings: settings,
          page: const EditProfileScreen(),
        );
      case AppRoutes.inviteFriends:
        return buildAppRoute(
          settings: settings,
          page: const InviteFriendsScreen(),
        );
      case AppRoutes.rewards:
        return buildAppRoute(settings: settings, page: const RewardsScreen());
      case AppRoutes.businessOnboarding:
        return buildAppRoute(
          settings: settings,
          page: const BusinessOnboardingScreen(),
        );
      case AppRoutes.businessDashboard:
        return buildAppRoute(
          settings: settings,
          page: const BusinessDashboardScreen(),
        );
      case AppRoutes.businessDeals:
        return buildAppRoute(
          settings: settings,
          page: const BusinessDealsScreen(),
        );
      case AppRoutes.createDeal:
        return buildAppRoute(
          settings: settings,
          page: const BusinessDealEditorScreen(),
        );
      case AppRoutes.editDeal:
        final args = _businessDealEditorArgs(settings);
        if (args == null) {
          return buildAppRoute(
            settings: settings,
            page: const BusinessDealsScreen(),
          );
        }
        return buildAppRoute(
          settings: settings,
          page: BusinessDealEditorScreen(dealId: args.dealId),
        );
      case AppRoutes.businessStories:
        return buildAppRoute(
          settings: settings,
          page: const BusinessStoriesScreen(),
        );
      case AppRoutes.createStory:
        return buildAppRoute(
          settings: settings,
          page: const CreateStoryScreen(),
        );
      case AppRoutes.manageBusinessProfile:
        return buildAppRoute(
          settings: settings,
          page: const ManageBusinessProfileScreen(),
        );
      case AppRoutes.analytics:
        return buildAppRoute(
          settings: settings,
          page: const BusinessAnalyticsScreen(),
        );
      case AppRoutes.redemptions:
        return buildAppRoute(
          settings: settings,
          page: const BusinessRedemptionsScreen(),
        );
      case AppRoutes.branches:
        return buildAppRoute(
          settings: settings,
          page: const BusinessBranchesScreen(),
        );
      default:
        return buildAppRoute(settings: settings, page: const SplashScreen());
    }
  }

  static Route<dynamic> _fallbackToShell(RouteSettings settings) {
    return buildAppRoute(settings: settings, page: const MainShell());
  }

  static StoryViewerArgs? _storyViewerArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is StoryViewerArgs) {
      return args;
    }
    if (args is String && args.trim().isNotEmpty) {
      return StoryViewerArgs(storyId: args.trim());
    }
    return null;
  }

  static SearchResultsArgs? _searchResultsArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is SearchResultsArgs) {
      return args;
    }
    if (args is String && args.trim().isNotEmpty) {
      return SearchResultsArgs(args.trim());
    }
    return null;
  }

  static CategoryFeedArgs? _categoryFeedArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is CategoryFeedArgs) {
      return args;
    }
    if (args is DealCategory) {
      return CategoryFeedArgs(args);
    }
    return null;
  }

  static DealRouteArgs? _dealRouteArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is DealRouteArgs) {
      return args;
    }
    if (args is String && args.trim().isNotEmpty) {
      return DealRouteArgs(args.trim());
    }
    return null;
  }

  static BusinessRouteArgs? _businessRouteArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is BusinessRouteArgs) {
      return args;
    }
    if (args is String && args.trim().isNotEmpty) {
      return BusinessRouteArgs(args.trim());
    }
    return null;
  }

  static BusinessDealEditorArgs? _businessDealEditorArgs(
    RouteSettings settings,
  ) {
    final args = settings.arguments;
    if (args is BusinessDealEditorArgs) {
      return args;
    }
    if (args is String && args.trim().isNotEmpty) {
      return BusinessDealEditorArgs(dealId: args.trim());
    }
    return null;
  }
}
