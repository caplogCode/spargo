import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/firebase_functions_config.dart';
import '../providers/app_language_provider.dart';
import 'generated_static_translations.dart';

@immutable
class AppTranslationState {
  const AppTranslationState({
    this.staticSourceTexts = const <String>{},
    this.translations = const <String, String>{},
    this.loading = false,
  });

  final Set<String> staticSourceTexts;
  final Map<String, String> translations;
  final bool loading;

  AppTranslationState copyWith({
    Set<String>? staticSourceTexts,
    Map<String, String>? translations,
    bool? loading,
  }) {
    return AppTranslationState(
      staticSourceTexts: staticSourceTexts ?? this.staticSourceTexts,
      translations: translations ?? this.translations,
      loading: loading ?? this.loading,
    );
  }
}

class AppTranslationController extends StateNotifier<AppTranslationState> {
  AppTranslationController(this.ref) : super(_initialState(ref)) {
    unawaited(_loadTranslationsForCurrentLanguage());
  }

  static const int _batchSize = 48;
  static const Duration _debounceDelay = Duration(milliseconds: 450);
  static const Duration _requestTimeout = Duration(seconds: 12);

  final Ref ref;
  final Set<String> _pending = <String>{};
  Timer? _debounce;

  String translate(String value) {
    final text = _normalizeUiText(value);
    if (text.isEmpty) {
      return value;
    }

    final languageCode = ref.read(appLanguageControllerProvider).languageCode;
    if (languageCode == 'de') {
      return value;
    }

    final translated =
        state.translations[text] ?? _bundledTranslations(languageCode)[text];
    if (translated != null && translated.trim().isNotEmpty) {
      return translated;
    }

    if (_shouldTranslate(text)) {
      _queue(text);
    }
    return value;
  }

  Future<void> reloadForLanguage() => _loadTranslationsForCurrentLanguage();

  Future<void> _loadTranslationsForCurrentLanguage() async {
    final languageCode = ref.read(appLanguageControllerProvider).languageCode;
    _pending.clear();
    _debounce?.cancel();
    if (languageCode == 'de') {
      state = state.copyWith(translations: const <String, String>{});
      return;
    }

    final bundled = _bundledTranslations(languageCode);
    state = state.copyWith(translations: bundled);

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(languageCode));
      final decoded = raw == null ? null : jsonDecode(raw);
      final cached = decoded is Map
          ? decoded.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{};
      final translations = <String, String>{...bundled, ...cached};
      state = state.copyWith(
        translations: Map<String, String>.unmodifiable(translations),
      );
      unawaited(_prefetchMissingTranslations(languageCode));
    } catch (error) {
      debugPrint('AppTranslationController cache load failed: $error');
      state = state.copyWith(translations: bundled);
      unawaited(_prefetchMissingTranslations(languageCode));
    }
  }

  bool _shouldTranslate(String text) {
    if (state.staticSourceTexts.isEmpty) {
      return false;
    }
    if (!state.staticSourceTexts.contains(text)) {
      return false;
    }
    if (text.length > 220) {
      return false;
    }
    if (RegExp(r'https?://|www\.|@|\{|\}|<|>|\$').hasMatch(text)) {
      return false;
    }
    if (!RegExp(r'[A-Za-zÄÖÜäöüßé]').hasMatch(text)) {
      return false;
    }
    return true;
  }

  void _queue(String text) {
    if (state.translations.containsKey(text)) {
      return;
    }
    _pending.add(text);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      unawaited(_flushPending());
    });
  }

  Future<void> _flushPending({
    bool requeueOnFailure = true,
    bool scheduleRetry = true,
  }) async {
    if (_pending.isEmpty || state.loading) {
      return;
    }
    final languageCode = ref.read(appLanguageControllerProvider).languageCode;
    if (languageCode == 'de') {
      _pending.clear();
      return;
    }

    final batch = _pending.take(_batchSize).toList(growable: false);
    _pending.removeAll(batch);
    state = state.copyWith(loading: true);
    try {
      final response = await http
          .post(
            firebaseFunctionUri('uiTranslateBatch'),
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'target': languageCode,
              'source': 'de',
              'texts': batch,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final translationsRaw = decoded is Map ? decoded['translations'] : null;
      if (translationsRaw is! Map) {
        throw StateError('Missing translations payload.');
      }

      final next = Map<String, String>.from(state.translations);
      for (final entry in translationsRaw.entries) {
        final key = _normalizeUiText(entry.key.toString());
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) {
          next[key] = value;
        }
      }
      state = state.copyWith(
        translations: Map<String, String>.unmodifiable(next),
      );
      await _saveCache(languageCode, next);
    } catch (error) {
      debugPrint('AppTranslationController translate failed: $error');
      if (requeueOnFailure) {
        _pending.addAll(batch);
      }
    } finally {
      state = state.copyWith(loading: false);
      if (scheduleRetry && _pending.isNotEmpty) {
        _debounce = Timer(const Duration(seconds: 4), () {
          unawaited(_flushPending());
        });
      }
    }
  }

  Future<void> _prefetchMissingTranslations(String languageCode) async {
    if (languageCode == 'de' || state.loading) {
      return;
    }
    final missing = state.staticSourceTexts
        .where(_shouldTranslate)
        .where((text) => !state.translations.containsKey(text))
        .toList(growable: false);
    if (missing.isEmpty) {
      return;
    }
    _pending.addAll(missing);
    while (_pending.isNotEmpty &&
        ref.read(appLanguageControllerProvider).languageCode == languageCode) {
      final before = _pending.length;
      await _flushPending(requeueOnFailure: false, scheduleRetry: false);
      if (_pending.length >= before) {
        break;
      }
    }
  }

  Future<void> _saveCache(
    String languageCode,
    Map<String, String> translations,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(languageCode), jsonEncode(translations));
    } catch (error) {
      debugPrint('AppTranslationController cache save failed: $error');
    }
  }

  String _cacheKey(String languageCode) =>
      'app.ui.translation.cache.v1.$languageCode';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

String _normalizeUiText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

AppTranslationState _initialState(Ref ref) {
  final languageCode = ref.read(appLanguageControllerProvider).languageCode;
  return AppTranslationState(
    staticSourceTexts: generatedStaticSourceTexts,
    translations: _bundledTranslations(languageCode),
  );
}

Map<String, String> _bundledTranslations(String languageCode) {
  if (languageCode == 'en') {
    return generatedStaticTranslationsEn;
  }
  return const <String, String>{};
}

final appTranslationControllerProvider =
    StateNotifierProvider<AppTranslationController, AppTranslationState>((ref) {
      final controller = AppTranslationController(ref);
      ref.listen<AppLanguageState>(appLanguageControllerProvider, (
        previous,
        next,
      ) {
        if (previous?.languageCode != next.languageCode) {
          unawaited(controller.reloadForLanguage());
        }
      });
      return controller;
    });
