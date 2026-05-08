import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/app_language_service.dart';
import '../../domain/models/user_models.dart';
import 'app_providers.dart';

const List<Locale> supportedAppLocales = <Locale>[Locale('de'), Locale('en')];

String normalizeAppLanguageCode(String value) {
  final normalized = value.trim().toLowerCase();
  return supportedAppLocales.any((locale) => locale.languageCode == normalized)
      ? normalized
      : 'de';
}

@immutable
class AppLanguageState {
  const AppLanguageState({
    required this.languageCode,
    required this.loaded,
    required this.hasLocalPreference,
  });

  const AppLanguageState.initial()
    : languageCode = 'de',
      loaded = false,
      hasLocalPreference = false;

  final String languageCode;
  final bool loaded;
  final bool hasLocalPreference;

  Locale get locale => Locale(languageCode);

  AppLanguageState copyWith({
    String? languageCode,
    bool? loaded,
    bool? hasLocalPreference,
  }) {
    return AppLanguageState(
      languageCode: languageCode ?? this.languageCode,
      loaded: loaded ?? this.loaded,
      hasLocalPreference: hasLocalPreference ?? this.hasLocalPreference,
    );
  }
}

class AppLanguageController extends StateNotifier<AppLanguageState> {
  AppLanguageController(this.ref, this._service)
    : super(const AppLanguageState.initial()) {
    unawaited(_load());
  }

  final Ref ref;
  final AppLanguageService _service;
  bool _remoteWriteInFlight = false;

  Future<void> _load() async {
    final localCode = normalizeAppLanguageCode(
      await _service.loadLanguageCode() ?? '',
    );
    final hasLocalPreference = await _service.loadLanguageCode() != null;
    final remoteCode = normalizeAppLanguageCode(
      ref.read(currentUserProvider).preferences.languageCode,
    );
    final resolvedCode = hasLocalPreference ? localCode : remoteCode;

    state = AppLanguageState(
      languageCode: resolvedCode,
      loaded: true,
      hasLocalPreference: hasLocalPreference,
    );
    await _applyAuthLanguage(resolvedCode);
  }

  void syncFromUser(User user) {
    if (!state.loaded || state.hasLocalPreference) {
      return;
    }
    final remoteCode = normalizeAppLanguageCode(user.preferences.languageCode);
    if (remoteCode == state.languageCode) {
      return;
    }
    unawaited(setLanguageCode(remoteCode, persistRemote: false));
  }

  Future<void> setLanguageCode(
    String languageCode, {
    bool persistRemote = true,
  }) async {
    final normalized = normalizeAppLanguageCode(languageCode);
    state = state.copyWith(
      languageCode: normalized,
      loaded: true,
      hasLocalPreference: true,
    );

    await _service.saveLanguageCode(normalized);
    await _applyAuthLanguage(normalized);

    if (!persistRemote || _remoteWriteInFlight) {
      return;
    }
    final session = ref.read(sessionControllerProvider);
    final authUser = ref.read(authUserProvider);
    if (!session.isAuthenticated ||
        authUser == null ||
        session.user.id.isEmpty) {
      return;
    }

    _remoteWriteInFlight = true;
    try {
      await ref
          .read(repositoryProvider)
          .updateUserSettings(user: session.user, languageCode: normalized);
    } catch (error) {
      debugPrint('AppLanguageController remote persist failed: $error');
    } finally {
      _remoteWriteInFlight = false;
    }
  }

  Future<void> _applyAuthLanguage(String languageCode) async {
    try {
      await firebase_auth.FirebaseAuth.instance.setLanguageCode(languageCode);
    } catch (error) {
      debugPrint('FirebaseAuth.setLanguageCode failed: $error');
    }
  }
}

final appLanguageControllerProvider =
    StateNotifierProvider<AppLanguageController, AppLanguageState>((ref) {
      final controller = AppLanguageController(ref, const AppLanguageService());
      ref.listen<User>(currentUserProvider, (previous, next) {
        controller.syncFromUser(next);
      });
      return controller;
    });
