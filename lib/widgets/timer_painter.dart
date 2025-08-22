import 'dart:math';
import 'package:flutter/material.dart';

class TimerPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  TimerPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) * 0.8;
    const strokeWidth = 15.0;

    // --- Background Track ---
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
    // FIX: Changed from 3.0 to 1.5 to make the circle thinner
      ..strokeWidth = 1.5;

    // Reverted to a simple circle for the track
    canvas.drawCircle(center, radius, trackPaint);


    // --- Progress Arc and Glow ---
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = progressColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

    double angle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      angle,
      false,
      glowPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      angle,
      false,
      progressPaint,
    );

    // --- Tick Marks ---
    final tickPaint = Paint()..color = Colors.white.withOpacity(0.5)..strokeWidth = 2;
    const tickLength = 5.0;
    const tickCount = 60;
    for (int i = 0; i < tickCount; i++) {
      final tickAngle = 2 * pi * i / tickCount;
      final isHourMark = i % 5 == 0;
      final currentTickLength = isHourMark ? tickLength * 2 : tickLength;

      final startX = center.dx + (radius + strokeWidth) * cos(tickAngle);
      final startY = center.dy + (radius + strokeWidth) * sin(tickAngle);
      final endX = center.dx + (radius + strokeWidth + currentTickLength) * cos(tickAngle);
      final endY = center.dy + (radius + strokeWidth + currentTickLength) * sin(tickAngle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}