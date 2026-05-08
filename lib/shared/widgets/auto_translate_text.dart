import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart'
    hide Text, TextStyle, StrutStyle, TextAlign, TextDirection, TextOverflow;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_translation_controller.dart';
import '../providers/app_language_provider.dart';

class AppTranslationScope extends InheritedWidget {
  const AppTranslationScope({
    super.key,
    required this.languageCode,
    required this.translationsIdentity,
    required super.child,
  });

  final String languageCode;
  final Object translationsIdentity;

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppTranslationScope>();
  }

  @override
  bool updateShouldNotify(covariant AppTranslationScope oldWidget) {
    return languageCode != oldWidget.languageCode ||
        !identical(translationsIdentity, oldWidget.translationsIdentity);
  }
}

class Text extends ConsumerWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final material.TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(appLanguageControllerProvider).languageCode;
    ref.watch(
      appTranslationControllerProvider.select((state) => state.translations),
    );
    final translator = ref.read(appTranslationControllerProvider.notifier);
    final effectiveLocale = locale ?? Locale(languageCode);

    if (textSpan != null) {
      return material.Text.rich(
        _translateSpan(textSpan!, translator),
        key: key,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: effectiveLocale,
        softWrap: softWrap,
        overflow: overflow,
        textScaleFactor: textScaleFactor,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }

    return material.Text(
      translator.translate(data ?? ''),
      key: key,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: effectiveLocale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null
          ? null
          : translator.translate(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }

  InlineSpan _translateSpan(
    InlineSpan span,
    AppTranslationController translator,
  ) {
    if (span is! TextSpan) {
      return span;
    }
    return TextSpan(
      text: span.text == null ? null : translator.translate(span.text!),
      children: span.children
          ?.map((child) => _translateSpan(child, translator))
          .toList(growable: false),
      style: span.style,
      recognizer: span.recognizer as GestureRecognizer?,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel == null
          ? null
          : translator.translate(span.semanticsLabel!),
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}

extension AppTranslationContextX on BuildContext {
  String t(String value) {
    AppTranslationScope.watch(this);
    return ProviderScope.containerOf(
      this,
      listen: false,
    ).read(appTranslationControllerProvider.notifier).translate(value);
  }
}
