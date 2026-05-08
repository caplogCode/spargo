import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../domain/models/nearby_place_models.dart';

@immutable
class PublicCouponBundle {
  const PublicCouponBundle({
    this.businesses = const <Business>[],
    this.deals = const <Deal>[],
  });

  final List<Business> businesses;
  final List<Deal> deals;
}

class PublicCouponScannerService {
  PublicCouponScannerService({required http.Client client}) : _client = client;

  final http.Client _client;
  bool _didLogWebCorsSkip = false;

  static const _couponWords = <String>[
    'gutschein',
    'rabatt',
    'aktion',
    'angebot',
    'special',
    'deal',
    'coupon',
    'happy hour',
    'gratis',
    'kostenlos',
    '2 fuer 1',
    '2 fur 1',
    '2 for 1',
    '2f1',
  ];

  static const _couponSlugs = <String>[
    'gutschein',
    'gutscheine',
    'gutscheinheft',
    'rabatt',
    'angebote',
    'aktion',
    'deals',
    'coupon',
    'specials',
    'promotions',
    'offers',
    'news',
    'blog',
    'events',
    'happy-hour',
  ];

  static const _blockedHosts = <String>[
    'duckduckgo.com',
    'google.com',
    'bing.com',
    'youtube.com',
    'tripadvisor.com',
    'yelp.com',
    'meinestadt.de',
    'restaurantguru.com',
    'mapcarta.com',
    'lieferando.de',
    'wolt.com',
    'ubereats.com',
  ];

  Future<PublicCouponBundle> scan({
    required NearbySearchArea area,
    required List<Business> businesses,
    required List<NearbyPlace> nearbyPlaces,
    Future<void> Function(PublicCouponBundle bundle)? onProgress,
  }) async {
    final candidates = await _buildCandidates(
      area: area,
      businesses: businesses,
      nearbyPlaces: nearbyPlaces,
    );
    if (candidates.isEmpty) {
      return const PublicCouponBundle();
    }

    final foundBusinesses = <String, Business>{};
    final foundDeals = <String, Deal>{};

    Future<void> emit() async {
      if (onProgress == null) {
        return;
      }
      await onProgress(
        PublicCouponBundle(
          businesses: foundBusinesses.values.toList(growable: false),
          deals: foundDeals.values.toList(growable: false),
        ),
      );
    }

    for (final candidate in candidates.take(16)) {
      await Future<void>.delayed(Duration.zero);
      final pages = await _candidatePages(candidate.websiteUrl);
      for (final pageUrl in pages) {
        final html = await _fetchHtml(pageUrl);
        if (html == null || html.isEmpty) {
          continue;
        }
        final offers = _extractOffers(
          html: html,
          pageUrl: pageUrl,
          candidate: candidate,
          area: area,
        );
        for (final offer in offers) {
          foundBusinesses[offer.business.id] = offer.business;
          foundDeals.putIfAbsent(
            _dealFingerprint(offer.deal),
            () => offer.deal,
          );
        }
      }
      if (foundDeals.isNotEmpty) {
        await emit();
      }
    }

    return PublicCouponBundle(
      businesses: foundBusinesses.values.toList(growable: false),
      deals: foundDeals.values.toList(growable: false),
    );
  }

  Future<List<_Candidate>> _buildCandidates({
    required NearbySearchArea area,
    required List<Business> businesses,
    required List<NearbyPlace> nearbyPlaces,
  }) async {
    final items = <_Candidate>[];
    final seenHosts = <String>{};

    void add(_Candidate candidate) {
      final normalized = _normalizeWebsite(candidate.websiteUrl);
      if (normalized == null) {
        return;
      }
      final host = _hostOf(normalized);
      if (host.isEmpty || !seenHosts.add(host)) {
        return;
      }
      items.add(candidate.copyWith(websiteUrl: normalized));
    }

    for (final business in businesses) {
      if (business.website.trim().isEmpty) {
        continue;
      }
      if (!_matchLabel(business.city, area.city) &&
          !_matchLabel(business.district, area.district)) {
        continue;
      }
      add(
        _Candidate(
          id: business.id,
          name: business.name,
          city: business.city,
          district: business.district,
          address: business.primaryBranch.address,
          latitude: business.primaryBranch.latitude,
          longitude: business.primaryBranch.longitude,
          category: business.category,
          palette: business.coverPalette,
          websiteUrl: business.website,
          existingBusiness: business,
          rating: business.rating,
          reviewCount: business.reviewCount,
          openNow: _openNowFromBusinessHours(business.primaryBranch.hours),
          imageUrl: business.imageUrl,
        ),
      );
    }

    for (final place in nearbyPlaces) {
      final website = place.websiteUrl?.trim() ?? '';
      if (website.isEmpty) {
        continue;
      }
      add(
        _Candidate(
          id: 'public_${_hash(website)}',
          name: place.name,
          city: area.city,
          district: area.district,
          address: place.address,
          latitude: place.latitude,
          longitude: place.longitude,
          category: place.category,
          palette: place.palette,
          websiteUrl: website,
          rating: place.rating,
          reviewCount: place.userRatingCount,
          openNow: place.openNow,
          imageUrl: place.photoUrl ?? '',
        ),
      );
    }

    if (!kIsWeb && items.length < 10 && area.city.trim().isNotEmpty) {
      for (final seed in await _discoverCitySeeds(area)) {
        add(seed);
      }
    }

    items.sort((a, b) => _distanceKm(area, a).compareTo(_distanceKm(area, b)));
    return items;
  }

  Future<List<_Candidate>> _discoverCitySeeds(NearbySearchArea area) async {
    final city = area.city.replaceAll('"', ' ').trim();
    if (city.isEmpty || city == 'Deutschlandweit') {
      return const <_Candidate>[];
    }
    final queries = <String>[
      '"$city" gutschein',
      '"$city" rabatt aktion',
      '"$city" angebote',
      '"$city" special deal',
      '"$city" happy hour',
      '"$city" fruehstueck gutschein',
      '"$city" brunch angebot',
      '"$city" cocktail happy hour',
      '"$city" juwelier rabatt',
      '"$city" erlebnis angebot',
      '"$city" freizeitpark angebot',
      '"$city" wellness gutschein',
      '"$city" kultur rabatt',
    ];
    final candidates = <_Candidate>[];
    final seen = <String>{};
    for (final query in queries) {
      final html = await _fetchText(
        'https://duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}',
      );
      if (html == null || html.isEmpty) {
        continue;
      }
      for (final hit in _searchHits(html)) {
        final url = _normalizeSearchResultUrl(hit.url);
        if (url == null || !_containsCouponSignal('${hit.title} $url')) {
          continue;
        }
        final host = _hostOf(url);
        if (host.isEmpty || !seen.add(host)) {
          continue;
        }
        candidates.add(
          _Candidate(
            id: 'seed_${_hash(url)}',
            name: hit.title.isEmpty ? host : hit.title,
            city: area.city,
            district: area.district,
            address: area.city,
            latitude: area.latitude,
            longitude: area.longitude,
            category: _inferCategory(hit.title),
            palette: const <int>[0xFFDB2149, 0xFFF06B84],
            websiteUrl: url,
            rating: 0,
            reviewCount: 0,
            openNow: null,
            imageUrl: '',
          ),
        );
        if (candidates.length >= 16) {
          return candidates;
        }
      }
    }
    return candidates;
  }

  Future<List<String>> _candidatePages(String websiteUrl) async {
    final normalized = _normalizeWebsite(websiteUrl);
    if (normalized == null) {
      return const <String>[];
    }
    final urls = <String>{normalized};
    final homepage = await _fetchHtml(normalized);
    if (homepage != null) {
      final anchorPattern = RegExp(
        r"""<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>""",
        caseSensitive: false,
      );
      for (final match in anchorPattern.allMatches(homepage)) {
        final href = match.group(1) ?? '';
        final label = _stripTags(match.group(2) ?? '');
        final lower = '$href $label'.toLowerCase();
        final isSocial =
            lower.contains('instagram.com') ||
            lower.contains('facebook.com') ||
            lower.contains('tiktok.com') ||
            lower.contains('linkedin.com') ||
            lower.contains('x.com') ||
            lower.contains('twitter.com');
        if (!_containsCouponSignal(lower) && !isSocial) {
          continue;
        }
        final absolute = _resolveUrl(normalized, href);
        if (absolute != null) {
          urls.add(absolute);
        }
        if (urls.length >= 8) {
          break;
        }
      }
    }
    for (final slug in _couponSlugs) {
      final url = _resolveUrl(normalized, '/$slug');
      if (url != null) {
        urls.add(url);
      }
      if (urls.length >= 8) {
        break;
      }
    }
    return urls.take(6).toList(growable: false);
  }

  List<_Offer> _extractOffers({
    required String html,
    required String pageUrl,
    required _Candidate candidate,
    required NearbySearchArea area,
  }) {
    final pageTitle = _firstMatch(html, r'<title[^>]*>([\s\S]*?)</title>');
    final bodyText = _cleanText(_visibleText(html));
    final title = _cleanTitle(
      _firstNonEmpty(<String>[pageTitle, candidate.name]),
    );
    final percent = _extractPercent(bodyText) ?? _implicitPercent(bodyText);
    if (!_containsCouponSignal(bodyText)) {
      return const <_Offer>[];
    }
    if (!_isLocallyRelevantOffer(
      title: title,
      bodyText: bodyText,
      candidate: candidate,
      area: area,
    )) {
      return const <_Offer>[];
    }

    final previewImageUrl = _extractPreviewImageUrl(html, pageUrl);
    final baseBusiness =
        candidate.existingBusiness ?? _syntheticBusiness(candidate);
    final business =
        previewImageUrl == null || baseBusiness.imageUrl.trim().isNotEmpty
        ? baseBusiness
        : baseBusiness.copyWith(imageUrl: previewImageUrl);
    final openNow = _openNowForCandidate(candidate, business);
    final availabilityLabel = openNow == null
        ? 'Website prüfen'
        : openNow
        ? 'Jetzt offen'
        : 'Gerade geschlossen';
    final highlightItems = <String>[
      'Von öffentlicher Website übernommen',
      if (percent != null) '$percent% Vorteil',
      if (openNow == true) 'Jetzt offen',
      if (openNow == false) 'Gerade geschlossen',
    ];
    final deal = Deal(
      id: 'publicdeal_${_hash('${business.id}|$pageUrl|$title')}',
      businessId: business.id,
      title: title,
      subtitle: percent == null
          ? 'Vorteil laut öffentlicher Website'
          : '$percent% Vorteil von der öffentlichen Website',
      description: _summarize(bodyText, 220),
      city: business.city,
      district: business.district,
      category: business.category,
      type: _inferType(bodyText),
      tags: <OfferTag>[OfferTag.fresh],
      distanceKm: _distanceKm(area, candidate),
      reviewCount: business.reviewCount,
      stats: DealStats(
        views: 0,
        saves: 0,
        activations: 0,
        redemptions: 0,
        rating: business.reviewCount > 0 ? business.rating : 0,
        friendCount: 0,
        todayRedemptions: 0,
      ),
      validUntil: DateTime.now().add(const Duration(days: 14)),
      originalPrice: 0,
      discountedPrice: 0,
      savingsPercent: percent ?? 0,
      priceHint: '\u00D6ffentlich verf\u00FCgbar',
      redemptionCode: '',
      highlights: highlightItems,
      conditions: const <String>[
        'Gilt nur nach Angaben auf der verlinkten Website.',
      ],
      galleryLabels: const <String>['Website Coupon'],
      palette: business.coverPalette,
      socialProof: '\u00D6ffentlich gefunden',
      availabilityLabel: availabilityLabel,
      ctaLabel: 'Zur Anbieter-Website',
      validDays: business.primaryBranch.hours
          .where((entry) => !entry.isClosed)
          .map((entry) => entry.day)
          .toList(growable: false),
      openNow: openNow == true,
      source: DealSource.thirdParty,
      sourceLabel: _hostOf(pageUrl),
      sourceUrl: pageUrl,
      imageUrl: previewImageUrl ?? business.imageUrl,
    );
    return <_Offer>[_Offer(business: business, deal: deal)];
  }

  bool _isLocallyRelevantOffer({
    required String title,
    required String bodyText,
    required _Candidate candidate,
    required NearbySearchArea area,
  }) {
    final combined = _normalizeLoose('$title $bodyText');
    final city = _normalizeLoose(
      candidate.city.isNotEmpty ? candidate.city : area.city,
    );
    final businessName = _normalizeLoose(candidate.name);
    final addressParts = candidate.address
        .split(',')
        .map(_normalizeLoose)
        .where((part) => part.length >= 4)
        .take(2)
        .toList(growable: false);
    final hasLocalSignal =
        (city.length >= 3 && combined.contains(city)) ||
        (businessName.length >= 5 && combined.contains(businessName)) ||
        addressParts.any(combined.contains);
    if (!hasLocalSignal) {
      return false;
    }

    final headline = _normalizeLoose(title);
    final broadCampaign = RegExp(
      r'\b(hundert|hunderten|hundreds|europa|europe|weltweit|worldwide|cityhotels|hotels?)\b',
      caseSensitive: false,
    ).hasMatch(headline);
    if (broadCampaign && city.isNotEmpty && !headline.contains(city)) {
      return false;
    }
    return true;
  }

  String _normalizeLoose(String value) {
    return _repair(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9äöüß]+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Business _syntheticBusiness(_Candidate candidate) => Business(
    id: candidate.id,
    name: candidate.name,
    tagline: '\u00D6ffentliche Website-Angebote',
    shortDescription: 'Automatisch erkannte Coupons von der Website.',
    description:
        'Automatisch aus einer Website in den sparGO Flow \u00FCbernommen.',
    category: candidate.category,
    city: candidate.city,
    district: candidate.district,
    rating: candidate.reviewCount > 0 ? candidate.rating : 0,
    reviewCount: candidate.reviewCount,
    followerCount: 0,
    priceLevel: '\u20AC\u20AC',
    tags: const <String>['\u00D6ffentlich'],
    coverPalette: candidate.palette,
    galleryLabels: const <String>['Website'],
    branches: <Branch>[
      Branch(
        id: '${candidate.id}_branch',
        name: candidate.name,
        city: candidate.city,
        district: candidate.district,
        address: candidate.address,
        latitude: candidate.latitude,
        longitude: candidate.longitude,
        hours: const <BusinessHours>[],
      ),
    ],
    phone: '',
    website: candidate.websiteUrl,
    distanceKm: 0,
    isTrending: false,
    isNew: true,
    analytics: const BusinessAnalytics(
      views: 0,
      saves: 0,
      activations: 0,
      redemptions: 0,
      reach: 0,
      trendPoints: <int>[0, 0, 0, 0],
    ),
    verificationStatus: BusinessVerificationStatus.draft,
    imageUrl: candidate.imageUrl,
  );

  Future<String?> _fetchHtml(String url) async {
    final text = await _fetchText(url);
    if (text == null || text.isEmpty) {
      return null;
    }
    return text.toLowerCase().contains('<html') ? text : null;
  }

  Future<String?> _fetchText(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    if (kIsWeb && !_sameOrigin(uri)) {
      if (!_didLogWebCorsSkip) {
        debugPrint(
          'Public coupon scan skipped cross-origin website fetches on web.',
        );
        _didLogWebCorsSkip = true;
      }
      return null;
    }
    try {
      final response = await _client
          .get(uri, headers: const <String, String>{'User-Agent': 'sparGO/1.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return _decodeBody(response);
    } catch (_) {
      return null;
    }
  }

  String _decodeBody(http.Response response) {
    final bytes = response.bodyBytes;
    try {
      return _repair(utf8.decode(bytes));
    } catch (_) {
      return _repair(latin1.decode(bytes, allowInvalid: true));
    }
  }

  String _repair(String value) {
    if (!value.contains('Ã')) {
      return value;
    }
    try {
      return utf8.decode(latin1.encode(value), allowMalformed: true);
    } catch (_) {
      return value;
    }
  }

  String _visibleText(String html) => _decodeEntities(
    html
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' '),
  );

  String _decodeEntities(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&auml;', '\u00E4')
      .replaceAll('&ouml;', '\u00F6')
      .replaceAll('&uuml;', '\u00FC')
      .replaceAll('&Auml;', '\u00C4')
      .replaceAll('&Ouml;', '\u00D6')
      .replaceAll('&Uuml;', '\u00DC')
      .replaceAll('&szlig;', '\u00DF');

  bool _containsCouponSignal(String value) {
    final normalized = value.toLowerCase();
    return _couponWords.any((word) => normalized.contains(word)) ||
        RegExp(r'\b\d{1,2}\s?(%|prozent)\b').hasMatch(normalized);
  }

  int? _extractPercent(String value) {
    const couponContext =
        r'(gutschein|rabatt|aktion|angebot|coupon|deal|special|vorteil|spare|sparen|nachlass)';
    final patterns = <RegExp>[
      RegExp(
        '$couponContext[^\\n\\r\\.,;:]{0,40}?(\\d{1,2})\\s?(%|prozent)',
        caseSensitive: false,
      ),
      RegExp(
        '(\\d{1,2})\\s?(%|prozent)[^\\n\\r\\.,;:]{0,40}?$couponContext',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final parsed = match == null ? null : int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed >= 1 && parsed <= 90) {
        return parsed;
      }
    }

    final allMatches = RegExp(
      r'(\d{1,2})\s?(%|prozent)',
      caseSensitive: false,
    ).allMatches(value);
    final candidates = allMatches
        .map((match) => int.tryParse(match.group(1) ?? ''))
        .whereType<int>()
        .where((value) => value >= 1 && value <= 90)
        .toSet()
        .toList(growable: false);

    return candidates.length == 1 ? candidates.first : null;
  }

  int? _implicitPercent(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('2 fuer 1') ||
        normalized.contains('2 fur 1') ||
        normalized.contains('2 for 1') ||
        normalized.contains('2f1')) {
      return 50;
    }
    return null;
  }

  bool? _openNowForCandidate(_Candidate candidate, Business business) {
    if (candidate.openNow != null) {
      return candidate.openNow;
    }
    return _openNowFromBusinessHours(business.primaryBranch.hours);
  }

  bool? _openNowFromBusinessHours(List<BusinessHours> hours) {
    if (hours.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    const weekdayMap = <int, String>{
      DateTime.monday: 'Mo',
      DateTime.tuesday: 'Di',
      DateTime.wednesday: 'Mi',
      DateTime.thursday: 'Do',
      DateTime.friday: 'Fr',
      DateTime.saturday: 'Sa',
      DateTime.sunday: 'So',
    };
    final weekday = weekdayMap[now.weekday];
    if (weekday == null) {
      return null;
    }
    final entry = hours.cast<BusinessHours?>().firstWhere(
      (value) => value?.day == weekday,
      orElse: () => null,
    );
    if (entry == null) {
      return null;
    }
    if (entry.isClosed) {
      return false;
    }
    final currentMinutes = now.hour * 60 + now.minute;
    final opensAt = _minutesOfDay(entry.opensAt);
    final closesAt = _minutesOfDay(entry.closesAt);
    if (opensAt == null || closesAt == null) {
      return null;
    }
    if (closesAt < opensAt) {
      return currentMinutes >= opensAt || currentMinutes <= closesAt;
    }
    return currentMinutes >= opensAt && currentMinutes <= closesAt;
  }

  int? _minutesOfDay(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null || minute == null) {
      return null;
    }
    final safeHour = hour.clamp(0, 23).toInt();
    final safeMinute = minute.clamp(0, 59).toInt();
    return (safeHour * 60) + safeMinute;
  }

  DealType _inferType(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('2 fuer 1') ||
        normalized.contains('2 fur 1') ||
        normalized.contains('2 for 1') ||
        normalized.contains('2f1')) {
      return DealType.twoForOne;
    }
    if (normalized.contains('happy hour')) {
      return DealType.happyHour;
    }
    if (normalized.contains('heute')) {
      return DealType.limitedTime;
    }
    return DealType.percentage;
  }

  String _cleanText(String value) {
    final text = _repair(value)
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(
            r'\b(font-family|box-sizing|critical|viewport|cookie|datenschutz|impressum)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[\{\}\[\]<>]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _summarize(text, 260);
  }

  String _cleanTitle(String value) {
    final title = _summarize(_cleanText(value), 72);
    if (title.isEmpty ||
        title.toLowerCase().contains('critical above-the-fold css') ||
        title.toLowerCase().contains('font-family') ||
        title.toLowerCase().contains('box-sizing')) {
      return 'Gutschein';
    }
    return title;
  }

  String _summarize(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3).trimRight()}...';
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final text = value.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _firstMatch(String text, String pattern) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
    return match == null
        ? ''
        : _stripTags(_decodeEntities(match.group(1) ?? '')).trim();
  }

  String? _extractPreviewImageUrl(String html, String pageUrl) {
    final metaMatch = RegExp(
      r'''<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(html);
    final metaUrl = metaMatch == null
        ? null
        : _resolveUrl(pageUrl, _decodeEntities(metaMatch.group(1) ?? ''));
    if (_isUsablePreviewImage(metaUrl)) {
      return metaUrl;
    }

    final imgMatch = RegExp(
      r'''<img[^>]+src=["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(html);
    final imgUrl = imgMatch == null
        ? null
        : _resolveUrl(pageUrl, _decodeEntities(imgMatch.group(1) ?? ''));
    if (_isUsablePreviewImage(imgUrl)) {
      return imgUrl;
    }

    return null;
  }

  bool _isUsablePreviewImage(String? value) {
    if (value == null) {
      return false;
    }
    final lower = value.toLowerCase();
    if (lower.startsWith('data:')) {
      return false;
    }
    if (lower.endsWith('.svg')) {
      return false;
    }
    return true;
  }

  List<_SearchHit> _searchHits(String html) {
    final hits = <_SearchHit>[];
    final pattern = RegExp(
      r"""<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>""",
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      hits.add(
        _SearchHit(
          url: _decodeEntities(match.group(1) ?? ''),
          title: _stripTags(_decodeEntities(match.group(2) ?? '')).trim(),
        ),
      );
      if (hits.length >= 24) {
        break;
      }
    }
    return hits;
  }

  String? _normalizeSearchResultUrl(String href) {
    final resolved = href.startsWith('//')
        ? 'https:$href'
        : href.startsWith('/')
        ? 'https://duckduckgo.com$href'
        : href;
    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      return null;
    }
    if (uri.host.contains('duckduckgo.com')) {
      final target = uri.queryParameters['uddg'];
      return target == null ? null : _normalizeWebsite(Uri.decodeFull(target));
    }
    return _normalizeWebsite(resolved);
  }

  String? _normalizeWebsite(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final withScheme = trimmed.startsWith('http')
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    if (_blockedHosts.any(
      (blocked) => uri.host == blocked || uri.host.endsWith('.$blocked'),
    )) {
      return null;
    }
    return uri.replace(fragment: '').toString();
  }

  String? _resolveUrl(String base, String target) {
    try {
      return _normalizeWebsite(Uri.parse(base).resolve(target).toString());
    } catch (_) {
      return null;
    }
  }

  String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri == null ? '' : uri.host.toLowerCase().replaceFirst('www.', '');
  }

  bool _sameOrigin(Uri uri) {
    final base = Uri.base;
    return uri.scheme == base.scheme &&
        uri.host == base.host &&
        uri.port == base.port;
  }

  bool _matchLabel(String left, String right) {
    final a = _slug(left);
    final b = _slug(right);
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    return a == b || a.contains(b) || b.contains(a);
  }

  DealCategory _inferCategory(String value) {
    final text = value.toLowerCase();
    if (text.contains('frühstück') ||
        text.contains('fruehstueck') ||
        text.contains('brunch') ||
        text.contains('bäckerei') ||
        text.contains('baeckerei')) {
      return DealCategory.breakfast;
    }
    if (text.contains('cocktail') ||
        text.contains('drink') ||
        text.contains('bier') ||
        text.contains('wein')) {
      return DealCategory.drinks;
    }
    if (text.contains('cafe') || text.contains('kaffee'))
      return DealCategory.cafe;
    if (text.contains('beauty') || text.contains('salon'))
      return DealCategory.beauty;
    if (text.contains('gesundheit') ||
        text.contains('apotheke') ||
        text.contains('arzt') ||
        text.contains('zahnarzt') ||
        text.contains('physio')) {
      return DealCategory.health;
    }
    if (text.contains('fitness') || text.contains('gym'))
      return DealCategory.fitness;
    if (text.contains('spa') || text.contains('wellness'))
      return DealCategory.wellness;
    if (text.contains('hotel') ||
        text.contains('reise') ||
        text.contains('urlaub') ||
        text.contains('travel')) {
      return DealCategory.travel;
    }
    if (text.contains('tier') ||
        text.contains('haustier') ||
        text.contains('pet')) {
      return DealCategory.pets;
    }
    if (text.contains('familie') ||
        text.contains('kinder') ||
        text.contains('kids') ||
        text.contains('baby')) {
      return DealCategory.family;
    }
    if (text.contains('möbel') ||
        text.contains('moebel') ||
        text.contains('wohnen') ||
        text.contains('home') ||
        text.contains('einrichtung')) {
      return DealCategory.home;
    }
    if (text.contains('auto') ||
        text.contains('reifen') ||
        text.contains('werkstatt') ||
        text.contains('fahrzeug')) {
      return DealCategory.automotive;
    }
    if (text.contains('museum') ||
        text.contains('theater') ||
        text.contains('kino') ||
        text.contains('galerie') ||
        text.contains('kultur')) {
      return DealCategory.culture;
    }
    if (text.contains('park') ||
        text.contains('spielplatz') ||
        text.contains('zoo') ||
        text.contains('aquarium')) {
      return DealCategory.parks;
    }
    if (text.contains('erlebnis') ||
        text.contains('escape') ||
        text.contains('bowling') ||
        text.contains('lasertag') ||
        text.contains('trampolin') ||
        text.contains('kart')) {
      return DealCategory.experiences;
    }
    if (text.contains('service') ||
        text.contains('reinigung') ||
        text.contains('wäscherei') ||
        text.contains('waescherei')) {
      return DealCategory.services;
    }
    if (text.contains('online') ||
        text.contains('onlineshop') ||
        text.contains('webshop')) {
      return DealCategory.online;
    }
    if (text.contains('shop') ||
        text.contains('store') ||
        text.contains('juwelier') ||
        text.contains('schmuck') ||
        text.contains('goldschmied') ||
        text.contains('uhr') ||
        text.contains('watch') ||
        text.contains('jewelry') ||
        text.contains('jewellery')) {
      return DealCategory.shopping;
    }
    if (text.contains('club') || text.contains('night'))
      return DealCategory.nightlife;
    if (text.contains('bar')) return DealCategory.drinks;
    if (text.contains('restaurant') || text.contains('bistro'))
      return DealCategory.food;
    return DealCategory.leisure;
  }

  String _stripTags(String value) => value.replaceAll(RegExp(r'<[^>]+>'), ' ');

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll('\u00E4', 'ae')
      .replaceAll('\u00F6', 'oe')
      .replaceAll('\u00FC', 'ue')
      .replaceAll('\u00DF', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  double _distanceKm(NearbySearchArea area, _Candidate candidate) {
    const earthRadiusKm = 6371.0;
    final deltaLat = _deg(candidate.latitude - area.latitude);
    final deltaLng = _deg(candidate.longitude - area.longitude);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(_deg(area.latitude)) *
            math.cos(_deg(candidate.latitude)) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _deg(double degree) => degree * (math.pi / 180);

  int _hash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  String _dealFingerprint(Deal deal) =>
      '${deal.businessId}|${_slug(deal.title)}|${deal.savingsPercent}|${deal.type.name}';
}

@immutable
class _Candidate {
  const _Candidate({
    required this.id,
    required this.name,
    required this.city,
    required this.district,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.palette,
    required this.websiteUrl,
    required this.rating,
    required this.reviewCount,
    required this.openNow,
    required this.imageUrl,
    this.existingBusiness,
  });

  final String id;
  final String name;
  final String city;
  final String district;
  final String address;
  final double latitude;
  final double longitude;
  final DealCategory category;
  final List<int> palette;
  final String websiteUrl;
  final double rating;
  final int reviewCount;
  final bool? openNow;
  final String imageUrl;
  final Business? existingBusiness;

  _Candidate copyWith({String? websiteUrl}) => _Candidate(
    id: id,
    name: name,
    city: city,
    district: district,
    address: address,
    latitude: latitude,
    longitude: longitude,
    category: category,
    palette: palette,
    websiteUrl: websiteUrl ?? this.websiteUrl,
    rating: rating,
    reviewCount: reviewCount,
    openNow: openNow,
    imageUrl: imageUrl,
    existingBusiness: existingBusiness,
  );
}

@immutable
class _Offer {
  const _Offer({required this.business, required this.deal});

  final Business business;
  final Deal deal;
}

@immutable
class _SearchHit {
  const _SearchHit({required this.url, required this.title});

  final String url;
  final String title;
}
