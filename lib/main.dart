import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/firebase_bootstrap.dart';
import 'theme/app_colors.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught platform error: $error');
        debugPrintStack(stackTrace: stack);
        return true;
      };

      ErrorWidget.builder = (details) {
        FlutterError.presentError(details);
        if (kReleaseMode) {
          return const ColoredBox(color: AppColors.background);
        }

        final message = details.exceptionAsString();
        return Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: AppColors.background,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                  child: Text(message),
                ),
              ),
            ),
          ),
        );
      };

      runApp(const ProviderScope(child: _BootstrapGate()));
    },
    (error, stack) {
      debugPrint('Uncaught zoned error: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  late Future<void> _bootstrapFuture = FirebaseBootstrap.ensureInitialized();
  bool _retryScheduled = false;

  void _retry() {
    setState(() {
      _retryScheduled = false;
      _bootstrapFuture = FirebaseBootstrap.ensureInitialized();
    });
  }

  void _scheduleSilentRetry() {
    if (_retryScheduled) {
      return;
    }
    _retryScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        _retry();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.error == null) {
          return const SpargoApp();
        }

        final failed = snapshot.error != null;
        if (failed && kReleaseMode) {
          _scheduleSilentRetry();
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateInitialRoutes: (initialRoute) {
            return <Route<dynamic>>[
              MaterialPageRoute<void>(
                settings: RouteSettings(name: initialRoute),
                builder: (_) => Scaffold(
                  backgroundColor: AppColors.background,
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 236,
                              height: 138,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(34),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.10,
                                    ),
                                    blurRadius: 38,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    height: 0.95,
                                    letterSpacing: 0,
                                  ),
                                  children: <TextSpan>[
                                    TextSpan(
                                      text: 'spar',
                                      style: TextStyle(color: AppColors.ink),
                                    ),
                                    TextSpan(
                                      text: 'GO',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (failed && !kReleaseMode) ...<Widget>[
                              const Text(
                                'Verbindung wird neu aufgebaut.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                kReleaseMode
                                    ? 'Bitte kurz erneut versuchen.'
                                    : '${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _retry,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primary,
                                ),
                                child: const Text('Erneut versuchen'),
                              ),
                            ] else ...<Widget>[
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'sparGO startet...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ];
          },
        );
      },
    );
  }
}
