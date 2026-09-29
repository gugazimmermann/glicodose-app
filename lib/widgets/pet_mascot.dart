import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:diabetes_app/services/pet_gamification.dart';
import 'package:diabetes_app/theme/app_theme.dart';

/// Drawn mascot that bobs, blinks, and sparkles when the day bar is full.
class PetMascot extends StatefulWidget {
  const PetMascot({
    super.key,
    required this.mood,
    this.accessoryId,
    this.size = 112,
  });

  final PetMood mood;
  final String? accessoryId;
  final double size;

  @override
  State<PetMascot> createState() => _PetMascotState();
}

class _PetMascotState extends State<PetMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final bob = math.sin(t * math.pi * 2) * 4;
        final blink = t > 0.42 && t < 0.48;
        final sparkle = widget.mood == PetMood.celebrating;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _PetPainter(
            mood: widget.mood,
            accessoryId: widget.accessoryId,
            bob: bob,
            blink: blink,
            sparklePhase: sparkle ? t : null,
            color: AppColors.primary,
          ),
        );
      },
    );
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter({
    required this.mood,
    required this.accessoryId,
    required this.bob,
    required this.blink,
    required this.sparklePhase,
    required this.color,
  });

  final PetMood mood;
  final String? accessoryId;
  final double bob;
  final bool blink;
  final double? sparklePhase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = color;
    final center = Offset(size.width / 2, size.height / 2 + 8 + bob);
    final radius = size.width * 0.28;
    canvas.drawCircle(center, radius, body);

    final ear = Paint()..color = color;
    canvas.drawCircle(center.translate(-radius * 0.7, -radius * 0.85), radius * 0.38, ear);
    canvas.drawCircle(center.translate(radius * 0.7, -radius * 0.85), radius * 0.38, ear);

    final eye = Paint()..color = Colors.white;
    final pupil = Paint()..color = const Color(0xFF1A2740);
    final left = center.translate(-radius * 0.35, -radius * 0.1);
    final right = center.translate(radius * 0.35, -radius * 0.1);
    if (blink || mood == PetMood.sleeping) {
      final lid = Paint()
        ..color = const Color(0xFF1A2740)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(left.translate(-6, 0), left.translate(6, 0), lid);
      canvas.drawLine(right.translate(-6, 0), right.translate(6, 0), lid);
    } else {
      canvas.drawCircle(left, 6, eye);
      canvas.drawCircle(right, 6, eye);
      canvas.drawCircle(left.translate(0, 1), 2.4, pupil);
      canvas.drawCircle(right.translate(0, 1), 2.4, pupil);
    }

    _paintAccessory(canvas, center, radius);

    if (sparklePhase != null) {
      final spark = Paint()..color = const Color(0xFFFFC107);
      for (var i = 0; i < 4; i++) {
        final angle = sparklePhase! * math.pi * 2 + i * 1.4;
        final dist = radius * (1.35 + 0.15 * math.sin(angle));
        canvas.drawCircle(
          center.translate(math.cos(angle) * dist, math.sin(angle) * dist * 0.7),
          2.2 + (i % 2),
          spark,
        );
      }
    }
  }

  void _paintAccessory(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = const Color(0xFFE31C23)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    switch (accessoryId) {
      case 'scarf':
        canvas.drawArc(
          Rect.fromCircle(center: center.translate(0, radius * 0.55), radius: radius * 0.55),
          0.2,
          2.6,
          false,
          paint,
        );
      case 'glasses':
        final glass = Paint()
          ..color = const Color(0xFF1A2740)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(center.translate(-radius * 0.35, -radius * 0.1), 9, glass);
        canvas.drawCircle(center.translate(radius * 0.35, -radius * 0.1), 9, glass);
        canvas.drawLine(
          center.translate(-radius * 0.05, -radius * 0.1),
          center.translate(radius * 0.05, -radius * 0.1),
          glass,
        );
      case 'cape':
        final cape = Paint()..color = const Color(0xFFE31C23).withValues(alpha: 0.85);
        final path = Path()
          ..moveTo(center.dx - radius * 0.2, center.dy)
          ..lineTo(center.dx - radius * 1.15, center.dy + radius * 0.9)
          ..lineTo(center.dx + radius * 0.15, center.dy + radius * 0.35)
          ..close();
        canvas.drawPath(path, cape);
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PetPainter oldDelegate) {
    return oldDelegate.bob != bob ||
        oldDelegate.blink != blink ||
        oldDelegate.mood != mood ||
        oldDelegate.accessoryId != accessoryId ||
        oldDelegate.sparklePhase != sparklePhase;
  }
}
