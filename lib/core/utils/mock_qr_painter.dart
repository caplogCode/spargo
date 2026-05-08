import 'dart:math' as math;

import 'package:flutter/material.dart';

class MockQrPainter extends CustomPainter {
  const MockQrPainter(this.seed);

  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    const grid = 21;
    final cell = size.width / grid;
    final background = Paint()..color = Colors.white;
    final foreground = Paint()..color = const Color(0xFF10211C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      background,
    );

    for (var y = 0; y < grid; y++) {
      for (var x = 0; x < grid; x++) {
        final value = seed.codeUnitAt((x * 7 + y * 11) % seed.length);
        final isFinder =
            (x < 5 && y < 5) || (x > 15 && y < 5) || (x < 5 && y > 15);
        final shouldDraw = isFinder || ((value + x + y) % 3 == 0);
        if (!shouldDraw) {
          continue;
        }

        final rect = Rect.fromLTWH(
          x * cell + 1.5,
          y * cell + 1.5,
          cell - 3,
          cell - 3,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          foreground,
        );
      }
    }

    final dots = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x1A10211C);
    for (var i = 0; i < 18; i++) {
      final angle = i / 18 * math.pi * 2;
      final point = Offset(
        size.width / 2 + math.cos(angle) * size.width * 0.42,
        size.height / 2 + math.sin(angle) * size.height * 0.42,
      );
      canvas.drawCircle(point, 1.5, dots);
    }
  }

  @override
  bool shouldRepaint(covariant MockQrPainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}
