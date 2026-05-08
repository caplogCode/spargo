import '../domain/models/deal_models.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const interests = '/interests';
  static const locationPermission = '/location-permission';
  static const login = '/login';
  static const register = '/register';
  static const businessRegister = '/business-register';
  static const shell = '/shell';
  static const storyViewer = '/story-viewer';
  static const search = '/search';
  static const searchResults = '/search-results';
  static const categories = '/categories';
  static const categoryFeed = '/category-feed';
  static const discover = '/discover';
  static const dealDetail = '/deal-detail';
  static const businessProfile = '/business-profile';
  static const saved = '/saved';
  static const activeDeals = '/active-deals';
  static const wallet = '/wallet';
  static const notifications = '/notifications';
  static const profile = '/profile';
  static const settings = '/settings';
  static const legal = '/legal';
  static const editProfile = '/edit-profile';
  static const inviteFriends = '/invite-friends';
  static const rewards = '/rewards';
  static const businessOnboarding = '/business-onboarding';
  static const businessDashboard = '/business-dashboard';
  static const businessDeals = '/business-deals';
  static const createDeal = '/business-deals/create';
  static const editDeal = '/business-deals/edit';
  static const businessStories = '/business-stories';
  static const createStory = '/business-stories/create';
  static const manageBusinessProfile = '/business-profile/manage';
  static const analytics = '/business-analytics';
  static const redemptions = '/business-redemptions';
  static const branches = '/business-branches';
}

class ShellArgs {
  const ShellArgs({this.initialIndex = 0});

  final int initialIndex;
}

class WelcomeArgs {
  const WelcomeArgs({this.initialStep = 0});

  final int initialStep;
}

class StoryViewerArgs {
  const StoryViewerArgs({required this.storyId, this.initialItemIndex = 0});

  final String storyId;
  final int initialItemIndex;
}

class DealRouteArgs {
  const DealRouteArgs(this.dealId);

  final String dealId;
}

class BusinessRouteArgs {
  const BusinessRouteArgs(this.businessId);

  final String businessId;
}

class CategoryFeedArgs {
  const CategoryFeedArgs(this.category);

  final DealCategory category;
}

class SearchResultsArgs {
  const SearchResultsArgs(this.query);

  final String query;
}

class WalletArgs {
  const WalletArgs({this.initialTab = 0});

  final int initialTab;
}

class BusinessDealEditorArgs {
  const BusinessDealEditorArgs({this.dealId});

  final String? dealId;
}
