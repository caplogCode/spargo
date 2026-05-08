import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:http/http.dart' as http;

import '../../core/config/google_maps_config.dart';
import '../../core/constants/app_tokens.dart';
import '../../core/config/firebase_functions_config.dart';
import '../../core/utils/web_image_proxy.dart';
import '../../theme/app_colors.dart';

@immutable
class DiscoveryMapPin {
  const DiscoveryMapPin({
    required this.id,
    required this.label,
    required this.initials,
    required this.alignment,
    this.palette = const <int>[0xFFDB2149, 0xFFF07B94, 0xFFFFF4F6],
    this.hasStory = false,
    this.isPublicCoupon = false,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.stackCount = 1,
  });

  final String id;
  final String label;
  final String initials;
  final Alignment alignment;
  final List<int> palette;
  final bool hasStory;
  final bool isPublicCoupon;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final int stackCount;
}

class DiscoveryMapSurface extends StatefulWidget {
  const DiscoveryMapSurface({
    super.key,
    required this.pins,
    required this.focusInitials,
    this.selectedPinId,
    this.onPinTap,
    this.showSearch = true,
    this.searchHint = 'Search',
    this.onSearchTap,
    this.onFilterTap,
    this.height,
    this.borderRadius = 0,
    this.focusAlignment = const Alignment(0.0, 0.32),
    this.showFocusPulse = true,
    this.interactive = true,
    this.compact = false,
    this.bottomOverlay,
    this.bottomInset = 0,
    this.centerLatitude,
    this.centerLongitude,
    this.zoom = 13.0,
    this.useLiveTiles = true,
    this.showAttribution = true,
  });

  final List<DiscoveryMapPin> pins;
  final String focusInitials;
  final String? selectedPinId;
  final ValueChanged<String>? onPinTap;
  final bool showSearch;
  final String searchHint;
  final VoidCallback? onSearchTap;
  final VoidCallback? onFilterTap;
  final double? height;
  final double borderRadius;
  final Alignment focusAlignment;
  final bool showFocusPulse;
  final bool interactive;
  final bool compact;
  final Widget? bottomOverlay;
  final double bottomInset;
  final double? centerLatitude;
  final double? centerLongitude;
  final double zoom;
  final bool useLiveTiles;
  final bool showAttribution;

  @override
  State<DiscoveryMapSurface> createState() => _DiscoveryMapSurfaceState();
}

class _DiscoveryMapSurfaceState extends State<DiscoveryMapSurface> {
  static const _fallbackCenter = gmaps.LatLng(53.14345, 8.21455);

  gmaps.GoogleMapController? _mapController;
  final Map<String, gmaps.BitmapDescriptor> _markerIconCache =
      <String, gmaps.BitmapDescriptor>{};
  final Set<String> _pendingMarkerKeys = <String>{};

  bool get _canRenderMapTiles =>
      widget.useLiveTiles &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test');

  bool get _useGoogleMap =>
      _canRenderMapTiles && !kIsWeb && hasGoogleMapsApiKey;

  bool get _useStaticGoogleMap => _canRenderMapTiles && kIsWeb;

  @override
  void initState() {
    super.initState();
    _prepareMarkerIcons();
    WidgetsBinding.instance.addPostFrameCallback((_) => _moveToFocus());
  }

  @override
  void didUpdateWidget(covariant DiscoveryMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedChanged = oldWidget.selectedPinId != widget.selectedPinId;
    final centerChanged =
        oldWidget.centerLatitude != widget.centerLatitude ||
        oldWidget.centerLongitude != widget.centerLongitude;
    if (selectedChanged || centerChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToFocus());
    }
    if (oldWidget.pins != widget.pins) {
      _prepareMarkerIcons();
    }
  }

  String _markerCacheKey(DiscoveryMapPin pin) {
    return [
      pin.id,
      pin.imageUrl ?? '',
      pin.hasStory ? 'story' : 'plain',
      pin.isPublicCoupon ? 'public' : 'native',
      'stack${pin.stackCount}',
    ].join('|');
  }

  void _prepareMarkerIcons() {
    if (!_useGoogleMap) {
      return;
    }
    for (final pin in widget.pins) {
      final cacheKey = _markerCacheKey(pin);
      if (_markerIconCache.containsKey(cacheKey) ||
          _pendingMarkerKeys.contains(cacheKey)) {
        continue;
      }
      _pendingMarkerKeys.add(cacheKey);
      unawaited(
        _buildMarkerIcon(pin)
            .then((icon) {
              _pendingMarkerKeys.remove(cacheKey);
              if (!mounted) {
                return;
              }
              setState(() {
                _markerIconCache[cacheKey] = icon;
              });
            })
            .catchError((_) {
              _pendingMarkerKeys.remove(cacheKey);
            }),
      );
    }
  }

  Future<gmaps.BitmapDescriptor> _buildMarkerIcon(DiscoveryMapPin pin) async {
    final bytes = await _paintMarkerBytesModern(pin);
    return gmaps.BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: 3,
      width: 82,
      height: 102,
    );
  }

  Future<Uint8List> _paintMarkerBytes(DiscoveryMapPin pin) async {
    const canvasWidth = 148.0;
    const canvasHeight = 176.0;
    const avatarRadius = 42.0;
    final center = Offset(canvasWidth / 2, 60);
    final primaryColor = Color(
      pin.palette.isNotEmpty ? pin.palette.first : 0xFFDB2149,
    );
    final secondaryColor = Color(
      pin.palette.length > 1 ? pin.palette[1] : 0xFFF07B94,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );
    final shadowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.22)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18);
    final glowPaint = Paint()
      ..color = secondaryColor.withValues(alpha: 0.16)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 28);

    canvas.drawCircle(
      center + const Offset(0, 14),
      avatarRadius + 10,
      glowPaint,
    );
    canvas.drawCircle(
      center + const Offset(0, 10),
      avatarRadius + 6,
      shadowPaint,
    );

    final pointerOuter = ui.Path()
      ..moveTo(center.dx - 18, center.dy + avatarRadius - 6)
      ..quadraticBezierTo(
        center.dx,
        center.dy + avatarRadius + 34,
        center.dx + 18,
        center.dy + avatarRadius - 6,
      )
      ..close();
    canvas.drawPath(
      pointerOuter,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - 18, center.dy),
          Offset(center.dx + 18, center.dy + avatarRadius + 30),
          <Color>[primaryColor, secondaryColor],
        ),
    );

    canvas.drawCircle(
      center,
      avatarRadius,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - avatarRadius, center.dy - avatarRadius),
          Offset(center.dx + avatarRadius, center.dy + avatarRadius),
          <Color>[primaryColor, secondaryColor],
        ),
    );
    canvas.drawCircle(center, avatarRadius - 4, Paint()..color = Colors.white);

    final imageRect = Rect.fromCircle(center: center, radius: avatarRadius - 8);
    final markerImage = await _loadMarkerImage(pin.imageUrl);
    if (markerImage != null) {
      canvas.save();
      canvas.clipPath(ui.Path()..addOval(imageRect));
      paintImage(
        canvas: canvas,
        rect: imageRect,
        image: markerImage,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();
    } else {
      canvas.drawOval(
        imageRect,
        Paint()
          ..shader = ui.Gradient.linear(
            imageRect.topLeft,
            imageRect.bottomRight,
            <Color>[primaryColor, secondaryColor],
          ),
      );
      final initialsPainter = TextPainter(
        text: TextSpan(
          text: pin.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 28,
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: imageRect.width);
      initialsPainter.paint(
        canvas,
        Offset(
          center.dx - (initialsPainter.width / 2),
          center.dy - (initialsPainter.height / 2),
        ),
      );
    }

    canvas.drawCircle(
      center,
      avatarRadius - 8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pin.hasStory ? 4 : 2.5
        ..color = pin.hasStory
            ? primaryColor.withValues(alpha: 0.92)
            : const Color(0x14DB2149),
    );

    if (pin.hasStory) {
      final badgeCenter = Offset(center.dx + 28, center.dy - 24);
      canvas.drawCircle(badgeCenter, 12, Paint()..color = primaryColor);
      final playPainter = TextPainter(
        text: const TextSpan(
          text: '▶',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      playPainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - (playPainter.width / 2) + 1,
          badgeCenter.dy - (playPainter.height / 2),
        ),
      );
    }

    if (pin.isPublicCoupon) {
      final badgeCenter = Offset(center.dx - 30, center.dy + 28);
      canvas.drawCircle(badgeCenter, 12, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeCenter,
        12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = primaryColor,
      );
      final publicPainter = TextPainter(
        text: TextSpan(
          text: 'P',
          style: TextStyle(
            color: primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      publicPainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - (publicPainter.width / 2),
          badgeCenter.dy - (publicPainter.height / 2),
        ),
      );
    }

    final renderedImage = await recorder.endRecording().toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await renderedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _paintMarkerBytesModern(DiscoveryMapPin pin) async {
    const canvasWidth = 214.0;
    const canvasHeight = 258.0;
    const avatarRadius = 61.0;
    final center = Offset(canvasWidth / 2, 88);
    final primaryColor = Color(
      pin.palette.isNotEmpty ? pin.palette.first : 0xFFDB2149,
    );
    final secondaryColor = Color(
      pin.palette.length > 1 ? pin.palette[1] : 0xFFF07B94,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    if (pin.stackCount > 1) {
      final backFill = Paint()..color = Colors.white;
      final backStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = primaryColor.withValues(alpha: 0.22);
      canvas.drawCircle(
        center + const Offset(-18, 22),
        avatarRadius - 3,
        backFill,
      );
      canvas.drawCircle(
        center + const Offset(-18, 22),
        avatarRadius - 3,
        backStroke,
      );
      canvas.drawCircle(
        center + const Offset(-9, 11),
        avatarRadius - 2,
        backFill,
      );
      canvas.drawCircle(
        center + const Offset(-9, 11),
        avatarRadius - 2,
        backStroke,
      );
    }

    final pointerOuter = ui.Path()
      ..moveTo(center.dx - 22, center.dy + avatarRadius - 4)
      ..quadraticBezierTo(
        center.dx,
        center.dy + avatarRadius + 48,
        center.dx + 22,
        center.dy + avatarRadius - 4,
      )
      ..close();
    canvas.drawPath(
      pointerOuter,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - 22, center.dy),
          Offset(center.dx + 22, center.dy + avatarRadius + 38),
          <Color>[primaryColor, secondaryColor],
        ),
    );

    canvas.drawCircle(
      center,
      avatarRadius,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - avatarRadius, center.dy - avatarRadius),
          Offset(center.dx + avatarRadius, center.dy + avatarRadius),
          <Color>[primaryColor, secondaryColor],
        ),
    );
    canvas.drawCircle(center, avatarRadius - 4, Paint()..color = Colors.white);

    final imageRect = Rect.fromCircle(center: center, radius: avatarRadius - 8);
    final markerImage = await _loadMarkerImage(pin.imageUrl);
    if (markerImage != null) {
      canvas.save();
      canvas.clipPath(ui.Path()..addOval(imageRect));
      paintImage(
        canvas: canvas,
        rect: imageRect,
        image: markerImage,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();
    } else {
      canvas.drawOval(
        imageRect,
        Paint()
          ..shader = ui.Gradient.linear(
            imageRect.topLeft,
            imageRect.bottomRight,
            <Color>[primaryColor, secondaryColor],
          ),
      );
      final initialsPainter = TextPainter(
        text: TextSpan(
          text: pin.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 32,
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: imageRect.width);
      initialsPainter.paint(
        canvas,
        Offset(
          center.dx - (initialsPainter.width / 2),
          center.dy - (initialsPainter.height / 2),
        ),
      );
    }

    canvas.drawCircle(
      center,
      avatarRadius - 8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pin.hasStory ? 4 : 2.5
        ..color = pin.hasStory
            ? primaryColor.withValues(alpha: 0.92)
            : const Color(0x14DB2149),
    );

    if (pin.hasStory) {
      final badgeCenter = Offset(center.dx + 38, center.dy - 34);
      canvas.drawCircle(badgeCenter, 15, Paint()..color = primaryColor);
      final playPainter = TextPainter(
        text: const TextSpan(
          text: '>',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      playPainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - (playPainter.width / 2) + 1,
          badgeCenter.dy - (playPainter.height / 2),
        ),
      );
    }

    if (pin.isPublicCoupon) {
      final badgeCenter = Offset(center.dx - 40, center.dy + 38);
      canvas.drawCircle(badgeCenter, 15, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeCenter,
        15,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = primaryColor,
      );
      final publicPainter = TextPainter(
        text: TextSpan(
          text: 'P',
          style: TextStyle(
            color: primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      publicPainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - (publicPainter.width / 2),
          badgeCenter.dy - (publicPainter.height / 2),
        ),
      );
    }

    if (pin.stackCount > 1) {
      final countText = pin.stackCount > 9 ? '9+' : '${pin.stackCount}';
      final badgeCenter = Offset(center.dx + 44, center.dy + 42);
      canvas.drawCircle(
        badgeCenter,
        18,
        Paint()..color = const Color(0xFF171315),
      );
      final countPainter = TextPainter(
        text: TextSpan(
          text: countText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      countPainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - (countPainter.width / 2),
          badgeCenter.dy - (countPainter.height / 2),
        ),
      );
    }

    final renderedImage = await recorder.endRecording().toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await renderedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  Future<ui.Image?> _loadMarkerImage(String? rawUrl) async {
    final resolvedUrl = webSafeImageUrl(rawUrl?.trim());
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      return null;
    }
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final codec = await ui.instantiateImageCodec(
      response.bodyBytes,
      targetWidth: 180,
      targetHeight: 180,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _moveToFocus() {
    if (!mounted) {
      return;
    }

    final target = _selectedPinPoint ?? _resolvedCenter;

    try {
      _mapController?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(target, widget.zoom),
      );
    } catch (_) {
      // Ignore first-layout sync issues.
    }
  }

  gmaps.LatLng get _resolvedCenter {
    final latitude = widget.centerLatitude;
    final longitude = widget.centerLongitude;
    if (latitude != null && longitude != null) {
      return gmaps.LatLng(latitude, longitude);
    }
    return _selectedPinPoint ??
        (widget.pins.isNotEmpty
            ? _pointFor(widget.pins.first, _fallbackCenter)
            : _fallbackCenter);
  }

  gmaps.LatLng? get _selectedPinPoint {
    if (widget.selectedPinId == null) {
      return null;
    }

    for (final pin in widget.pins) {
      if (pin.id == widget.selectedPinId) {
        return _pointFor(pin, _fallbackCenter);
      }
    }
    return null;
  }

  gmaps.LatLng _pointFor(DiscoveryMapPin pin, gmaps.LatLng fallbackCenter) {
    if (pin.latitude != null && pin.longitude != null) {
      return gmaps.LatLng(pin.latitude!, pin.longitude!);
    }

    final center = _resolvedPseudoCenter(fallbackCenter);
    final latitude = center.latitude - (pin.alignment.y * 0.018);
    final longitude = center.longitude + (pin.alignment.x * 0.030);
    return gmaps.LatLng(latitude, longitude);
  }

  gmaps.LatLng _resolvedPseudoCenter(gmaps.LatLng fallbackCenter) {
    final latitude = widget.centerLatitude;
    final longitude = widget.centerLongitude;
    if (latitude != null && longitude != null) {
      return gmaps.LatLng(latitude, longitude);
    }
    return fallbackCenter;
  }

  @override
  Widget build(BuildContext context) {
    final center = _resolvedCenter;
    final searchTopInset =
        MediaQuery.of(context).padding.top + (widget.compact ? 18 : 28);

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedHeight =
            widget.height ??
            (constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : widget.compact
                ? 260.0
                : 320.0);

        final surface = SizedBox(
          height: resolvedHeight,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: _buildMapBase(
                    center,
                    constraints.maxWidth,
                    resolvedHeight,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.18),
                            Colors.transparent,
                            const Color(0xFFE8EDF2).withValues(alpha: 0.34),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_useGoogleMap && !_useStaticGoogleMap)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _MapBackdropPainter()),
                    ),
                  ),
                if (!_useGoogleMap)
                  ..._buildOverlayPins(
                    width: constraints.maxWidth,
                    height: resolvedHeight,
                    center: center,
                  ),
                if (widget.showSearch)
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: searchTopInset,
                    child: _SearchPlate(
                      hint: widget.searchHint,
                      onTap: widget.onSearchTap,
                      onFilterTap: widget.onFilterTap,
                    ),
                  ),
                if (widget.showFocusPulse)
                  Align(
                    alignment: widget.focusAlignment,
                    child: IgnorePointer(
                      child: _FocusPulseAvatar(
                        initials: widget.focusInitials,
                        compact: widget.compact,
                      ),
                    ),
                  ),
                if (widget.bottomOverlay != null)
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom:
                        (widget.compact ? AppSpacing.lg : AppSpacing.xl) +
                        widget.bottomInset,
                    child: widget.bottomOverlay!,
                  ),
              ],
            ),
          ),
        );

        if (widget.borderRadius <= 0) {
          return surface;
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: surface,
        );
      },
    );
  }

  Widget _buildMapBase(
    gmaps.LatLng center,
    double width,
    double resolvedHeight,
  ) {
    if (_useGoogleMap) {
      return gmaps.GoogleMap(
        initialCameraPosition: gmaps.CameraPosition(
          target: center,
          zoom: widget.zoom,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
          _moveToFocus();
        },
        mapType: gmaps.MapType.normal,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        scrollGesturesEnabled: widget.interactive,
        zoomGesturesEnabled: widget.interactive,
        markers: _buildMarkers(center),
      );
    }

    if (_useStaticGoogleMap) {
      return Image.network(
        _buildStaticMapUrl(
          center: center,
          width: width.round(),
          height: resolvedHeight.round(),
        ),
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.expand();
        },
      );
    }

    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFF6F7F9), Color(0xFFEFF2F5)],
        ),
      ),
    );
  }

  Set<gmaps.Marker> _buildMarkers(gmaps.LatLng center) {
    return widget.pins.map((pin) {
      final markerIcon =
          _markerIconCache[_markerCacheKey(pin)] ??
          gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRose,
          );
      return gmaps.Marker(
        markerId: gmaps.MarkerId(pin.id),
        position: _pointFor(pin, center),
        infoWindow: gmaps.InfoWindow(title: pin.label),
        zIndexInt: pin.id == widget.selectedPinId ? 10 : 1,
        anchor: const Offset(0.5, 1),
        onTap: widget.onPinTap == null ? null : () => widget.onPinTap!(pin.id),
        icon: markerIcon,
      );
    }).toSet();
  }

  String _buildStaticMapUrl({
    required gmaps.LatLng center,
    required int width,
    required int height,
  }) {
    return firebaseFunctionUri(
      'googleMapsStaticMap',
      queryParameters: <String, String>{
        'centerLat': center.latitude.toString(),
        'centerLng': center.longitude.toString(),
        'zoom': widget.zoom.toStringAsFixed(2),
        'width': width.clamp(220, 640).toString(),
        'height': height.clamp(220, 640).toString(),
      },
    ).toString();
  }

  List<Widget> _buildOverlayPins({
    required double width,
    required double height,
    required gmaps.LatLng center,
  }) {
    final frameSize = widget.compact ? 80.0 : 92.0;
    final children = <Widget>[];

    for (final pin in widget.pins) {
      final offset = _resolvePinOffset(
        pin: pin,
        center: center,
        width: width,
        height: height,
      );
      if (offset == null) {
        continue;
      }

      children.add(
        Positioned(
          left: offset.dx - (frameSize / 2),
          top: offset.dy - (frameSize / 2),
          child: _MapAvatarPin(
            pin: pin,
            selected: pin.id == widget.selectedPinId,
            compact: widget.compact,
            onTap: widget.onPinTap == null
                ? null
                : () => widget.onPinTap!(pin.id),
          ),
        ),
      );
    }

    return children;
  }

  Offset? _resolvePinOffset({
    required DiscoveryMapPin pin,
    required gmaps.LatLng center,
    required double width,
    required double height,
  }) {
    final anchorY = height * 0.38;
    if (pin.latitude != null && pin.longitude != null) {
      final centerPoint = _projectLatLng(center.latitude, center.longitude);
      final pinPoint = _projectLatLng(pin.latitude!, pin.longitude!);
      final scale = 256.0 * math.pow(2.0, widget.zoom).toDouble();
      final dx = (pinPoint.dx - centerPoint.dx) * scale;
      final dy = (pinPoint.dy - centerPoint.dy) * scale;
      final x = (width / 2) + dx;
      final y = anchorY + dy;

      if (x < -80 || x > width + 80 || y < -80 || y > height + 80) {
        return null;
      }
      return Offset(x, y);
    }

    return Offset(
      ((pin.alignment.x + 1) / 2) * width,
      anchorY + (pin.alignment.y * height * 0.24),
    );
  }

  Offset _projectLatLng(double latitude, double longitude) {
    final siny = math
        .sin(latitude * math.pi / 180)
        .clamp(-0.9999, 0.9999)
        .toDouble();
    return Offset(
      (longitude + 180) / 360,
      0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi),
    );
  }
}

class _SearchPlate extends StatelessWidget {
  const _SearchPlate({
    required this.hint,
    this.onTap,
    required this.onFilterTap,
  });

  final String hint;
  final VoidCallback? onTap;
  final VoidCallback? onFilterTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(26),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: Colors.black.withValues(alpha: 0.28),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onFilterTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6F8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.secondary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusPulseAvatar extends StatelessWidget {
  const _FocusPulseAvatar({required this.initials, required this.compact});

  final String initials;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final outer = compact ? 144.0 : 184.0;
    final mid = compact ? 98.0 : 128.0;
    final inner = compact ? 62.0 : 84.0;

    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: outer,
            height: outer,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x14DB2149),
            ),
          ),
          Container(
            width: mid,
            height: mid,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x22DB2149),
            ),
          ),
          Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFAE7C5D), Color(0xFFDFC2A4)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapAvatarPin extends StatelessWidget {
  const _MapAvatarPin({
    required this.pin,
    required this.selected,
    required this.compact,
    this.onTap,
  });

  final DiscoveryMapPin pin;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final frameSize = compact ? 80.0 : 92.0;
    final avatarSize = compact ? 56.0 : 66.0;
    final borderWidth = pin.hasStory ? 4.0 : 3.0;
    final pinColor = AppColors.primary;
    final resolvedImageUrl = webSafeImageUrl(pin.imageUrl);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        scale: selected ? 1.08 : 1,
        child: SizedBox(
          width: frameSize,
          height: frameSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (pin.stackCount > 1)
                Positioned(
                  left: 6,
                  top: 10,
                  child: Container(
                    width: frameSize - 8,
                    height: frameSize - 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: pinColor.withValues(alpha: 0.18),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              if (pin.stackCount > 1)
                Positioned(
                  left: 3,
                  top: 5,
                  child: Container(
                    width: frameSize - 4,
                    height: frameSize - 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: pinColor.withValues(alpha: 0.22),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              if (pin.hasStory)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: pinColor.withValues(
                          alpha: selected ? 0.30 : 0.18,
                        ),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              if (pin.hasStory)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: compact ? 20 : 24,
                    height: compact ? 20 : 24,
                    decoration: BoxDecoration(
                      color: pinColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (pin.isPublicCoupon)
                Positioned(
                  left: -1,
                  bottom: -1,
                  child: Container(
                    width: compact ? 20 : 24,
                    height: compact ? 20 : 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: pinColor, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.public_rounded,
                      size: 12,
                      color: pinColor,
                    ),
                  ),
                ),
              Container(
                width: frameSize,
                height: frameSize,
                padding: EdgeInsets.all(borderWidth),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: pinColor, width: borderWidth),
                ),
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: resolvedImageUrl == null
                      ? Center(
                          child: Text(
                            pin.initials,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: pinColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        )
                      : Image.network(
                          resolvedImageUrl,
                          fit: BoxFit.cover,
                          webHtmlElementStrategy:
                              WebHtmlElementStrategy.fallback,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                pin.initials,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: pinColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              if (pin.stackCount > 1)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171315),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      pin.stackCount > 9 ? '9+' : '${pin.stackCount}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final majorRoadPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;

    final majorRoadInnerPaint = Paint()
      ..color = const Color(0xFFEDEFF2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;

    final minorRoadPaint = Paint()
      ..color = const Color(0xFFF7F8FA)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    final riverPaint = Paint()
      ..color = const Color(0xFFD9ECFF)
      ..style = PaintingStyle.fill;

    final parkPaint = Paint()
      ..color = const Color(0xFFE6F4EA)
      ..style = PaintingStyle.fill;

    final river = Path()
      ..moveTo(size.width * 0.72, -20)
      ..quadraticBezierTo(
        size.width * 0.92,
        size.height * 0.18,
        size.width * 0.80,
        size.height * 0.44,
      )
      ..quadraticBezierTo(
        size.width * 0.64,
        size.height * 0.72,
        size.width * 0.82,
        size.height + 24,
      )
      ..lineTo(size.width + 24, size.height + 24)
      ..lineTo(size.width + 24, -24)
      ..close();
    canvas.drawPath(river, riverPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.05,
          size.height * 0.10,
          size.width * 0.22,
          size.height * 0.18,
        ),
        const Radius.circular(18),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.16,
          size.height * 0.62,
          size.width * 0.18,
          size.height * 0.13,
        ),
        const Radius.circular(16),
      ),
      parkPaint,
    );

    final paths = <List<Offset>>[
      _points(size, const <Offset>[
        Offset(0.00, 0.12),
        Offset(0.18, 0.24),
        Offset(0.40, 0.16),
        Offset(0.62, 0.28),
        Offset(0.88, 0.20),
      ]),
      _points(size, const <Offset>[
        Offset(0.04, 0.34),
        Offset(0.26, 0.28),
        Offset(0.52, 0.40),
        Offset(0.74, 0.34),
        Offset(0.98, 0.48),
      ]),
      _points(size, const <Offset>[
        Offset(0.00, 0.58),
        Offset(0.22, 0.48),
        Offset(0.48, 0.62),
        Offset(0.68, 0.54),
        Offset(0.94, 0.66),
      ]),
      _points(size, const <Offset>[
        Offset(0.06, 0.82),
        Offset(0.28, 0.70),
        Offset(0.56, 0.82),
        Offset(0.72, 0.76),
        Offset(0.98, 0.92),
      ]),
    ];

    for (final points in paths) {
      _drawPath(canvas, points, majorRoadPaint);
      _drawPath(canvas, points, majorRoadInnerPaint);
    }

    for (var i = 0; i < 8; i++) {
      final x = size.width * (0.08 + (i * 0.11));
      final points = <Offset>[
        Offset(x, 0),
        Offset(x + 10, size.height * 0.24),
        Offset(x - 8, size.height * 0.54),
        Offset(x + 14, size.height),
      ];
      _drawPath(canvas, points, minorRoadPaint);
    }
  }

  List<Offset> _points(Size size, List<Offset> factors) {
    return factors
        .map((point) => Offset(point.dx * size.width, point.dy * size.height))
        .toList(growable: false);
  }

  void _drawPath(Canvas canvas, List<Offset> points, Paint paint) {
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midpoint = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        midpoint.dx,
        midpoint.dy,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
