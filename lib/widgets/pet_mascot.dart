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

class _PetMascotState extends State<PetMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: widget.mood == PetMood.sleeping ? 4200 : 2800,
      ),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant PetMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _controller.duration = Duration(
        milliseconds: widget.mood == PetMood.sleeping ? 4200 : 2800,
      );
      _controller.repeat();
    }
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
        final sleep = widget.mood == PetMood.sleeping;
        final celebrate = widget.mood == PetMood.celebrating;
        final waiting = widget.mood == PetMood.waiting;
        final bobAmp = sleep ? 2.0 : (celebrate ? 5.0 : 3.5);
        final bob = math.sin(t * math.pi * 2) * bobAmp;
        final blink = !sleep && t > 0.42 && t < 0.48;
        final tilt = waiting ? math.sin(t * math.pi * 2) * 0.06 : 0.0;
        final squash = celebrate
            ? 1 + math.sin(t * math.pi * 4) * 0.04
            : 1.0;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _PetPainter(
            mood: widget.mood,
            accessoryId: widget.accessoryId,
            bob: bob,
            blink: blink,
            tilt: tilt,
            squash: squash,
            phase: t,
            color: AppColors.primary,
            colorDark: AppColors.primaryDark,
            colorSoft: AppColors.primarySoft,
            accent: AppColors.accent,
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
    required this.tilt,
    required this.squash,
    required this.phase,
    required this.color,
    required this.colorDark,
    required this.colorSoft,
    required this.accent,
  });

  final PetMood mood;
  final String? accessoryId;
  final double bob;
  final bool blink;
  final double tilt;
  final double squash;
  final double phase;
  final Color color;
  final Color colorDark;
  final Color colorSoft;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + size.height * 0.04 + bob;
    final bodyW = size.width * 0.56 * squash;
    final bodyH = size.height * 0.52 / squash;
    final center = Offset(cx, cy);
    final radius = bodyW / 2;

    _paintShadow(canvas, size, center, radius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.translate(-center.dx, -center.dy);

    if (accessoryId == 'cape') {
      _paintCape(canvas, center, radius, behind: true);
    }

    _paintEars(canvas, center, radius);
    _paintBody(canvas, center, bodyW, bodyH);
    _paintBelly(canvas, center, bodyW, bodyH);
    _paintFace(canvas, center, radius);

    if (accessoryId == 'scarf') {
      _paintScarf(canvas, center, radius);
    } else if (accessoryId == 'glasses') {
      _paintGlasses(canvas, center, radius);
    } else if (accessoryId == 'cape') {
      _paintCape(canvas, center, radius, behind: false);
    }

    if (mood == PetMood.celebrating) {
      _paintSparkles(canvas, center, radius);
    }
    if (mood == PetMood.sleeping) {
      _paintZzz(canvas, center, radius);
    }

    canvas.restore();
  }

  void _paintShadow(Canvas canvas, Size size, Offset center, double radius) {
    final shadowCenter = Offset(
      size.width / 2,
      size.height * 0.86 + bob * 0.15,
    );
    final shadow = Paint()
      ..color = colorDark.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: shadowCenter,
        width: radius * 1.55,
        height: radius * 0.35,
      ),
      shadow,
    );
  }

  void _paintEars(Canvas canvas, Offset center, double radius) {
    final earFill = Paint()
      ..shader = RadialGradient(
        colors: [Color.lerp(color, Colors.white, 0.12)!, colorDark],
        center: const Alignment(-0.3, -0.35),
        radius: 0.9,
      ).createShader(
        Rect.fromCircle(
          center: center.translate(-radius * 0.72, -radius * 0.78),
          radius: radius * 0.42,
        ),
      );
    final rightFill = Paint()
      ..shader = RadialGradient(
        colors: [Color.lerp(color, Colors.white, 0.12)!, colorDark],
        center: const Alignment(0.3, -0.35),
        radius: 0.9,
      ).createShader(
        Rect.fromCircle(
          center: center.translate(radius * 0.72, -radius * 0.78),
          radius: radius * 0.42,
        ),
      );
    final left = center.translate(-radius * 0.72, -radius * 0.78);
    final right = center.translate(radius * 0.72, -radius * 0.78);
    canvas.drawCircle(left, radius * 0.4, earFill);
    canvas.drawCircle(right, radius * 0.4, rightFill);

    final inner = Paint()..color = colorSoft.withValues(alpha: 0.9);
    canvas.drawCircle(left.translate(0, radius * 0.04), radius * 0.2, inner);
    canvas.drawCircle(right.translate(0, radius * 0.04), radius * 0.2, inner);
  }

  void _paintBody(
    Canvas canvas,
    Offset center,
    double bodyW,
    double bodyH,
  ) {
    final rect = Rect.fromCenter(center: center, width: bodyW, height: bodyH);
    final body = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(color, Colors.white, 0.22)!,
          color,
          colorDark,
        ],
        stops: const [0.0, 0.55, 1.0],
        center: const Alignment(-0.25, -0.35),
        radius: 1.05,
      ).createShader(rect);
    canvas.drawOval(rect, body);

    final rim = Paint()
      ..color = colorDark.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, bodyW * 0.02);
    canvas.drawOval(rect.deflate(1), rim);
  }

  void _paintBelly(
    Canvas canvas,
    Offset center,
    double bodyW,
    double bodyH,
  ) {
    final belly = Paint()..color = colorSoft.withValues(alpha: 0.95);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, bodyH * 0.12),
        width: bodyW * 0.55,
        height: bodyH * 0.42,
      ),
      belly,
    );
  }

  void _paintFace(Canvas canvas, Offset center, double radius) {
    final eyeR = math.max(4.5, radius * 0.22);
    final left = center.translate(-radius * 0.32, -radius * 0.08);
    final right = center.translate(radius * 0.32, -radius * 0.08);
    final closed = blink || mood == PetMood.sleeping;

    if (closed) {
      final lid = Paint()
        ..color = colorDark
        ..strokeWidth = math.max(2.0, radius * 0.08)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final half = eyeR * 0.85;
      canvas.drawLine(left.translate(-half, 0), left.translate(half, 0), lid);
      canvas.drawLine(right.translate(-half, 0), right.translate(half, 0), lid);
    } else {
      final white = Paint()..color = Colors.white;
      final pupil = Paint()..color = const Color(0xFF1A2740);
      final shine = Paint()..color = Colors.white;
      canvas.drawCircle(left, eyeR, white);
      canvas.drawCircle(right, eyeR, white);
      final look = Offset(0, eyeR * 0.18);
      final pupilR = eyeR * 0.42;
      canvas.drawCircle(left + look, pupilR, pupil);
      canvas.drawCircle(right + look, pupilR, pupil);
      canvas.drawCircle(
        left + look.translate(-pupilR * 0.35, -pupilR * 0.4),
        pupilR * 0.28,
        shine,
      );
      canvas.drawCircle(
        right + look.translate(-pupilR * 0.35, -pupilR * 0.4),
        pupilR * 0.28,
        shine,
      );
    }

    final cheek = Paint()..color = const Color(0xFFFF8A9A).withValues(alpha: 0.35);
    final cheekR = radius * 0.14;
    canvas.drawCircle(
      center.translate(-radius * 0.55, radius * 0.22),
      cheekR,
      cheek,
    );
    canvas.drawCircle(
      center.translate(radius * 0.55, radius * 0.22),
      cheekR,
      cheek,
    );

    _paintMouth(canvas, center, radius);
  }

  void _paintMouth(Canvas canvas, Offset center, double radius) {
    final mouth = Paint()
      ..color = colorDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, radius * 0.07)
      ..strokeCap = StrokeCap.round;
    final origin = center.translate(0, radius * 0.28);

    switch (mood) {
      case PetMood.celebrating:
        final fill = Paint()..color = const Color(0xFF1A2740);
        final open = Path()
          ..moveTo(origin.dx - radius * 0.18, origin.dy)
          ..quadraticBezierTo(
            origin.dx,
            origin.dy + radius * 0.28,
            origin.dx + radius * 0.18,
            origin.dy,
          )
          ..close();
        canvas.drawPath(open, fill);
        canvas.drawPath(open, mouth);
      case PetMood.waiting:
        canvas.drawArc(
          Rect.fromCenter(
            center: origin.translate(0, radius * 0.08),
            width: radius * 0.3,
            height: radius * 0.18,
          ),
          math.pi + 0.25,
          math.pi - 0.5,
          false,
          mouth,
        );
      case PetMood.sleeping:
        canvas.drawArc(
          Rect.fromCenter(
            center: origin,
            width: radius * 0.28,
            height: radius * 0.16,
          ),
          0.2,
          math.pi - 0.4,
          false,
          mouth,
        );
      case PetMood.curious:
        canvas.drawArc(
          Rect.fromCenter(
            center: origin.translate(0, -radius * 0.02),
            width: radius * 0.36,
            height: radius * 0.28,
          ),
          0.15,
          math.pi - 0.3,
          false,
          mouth,
        );
    }
  }

  void _paintScarf(Canvas canvas, Offset center, double radius) {
    final fill = Paint()..color = accent;
    final stroke = Paint()
      ..color = Color.lerp(accent, Colors.black, 0.15)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, radius * 0.05)
      ..strokeCap = StrokeCap.round;
    final band = Path()
      ..moveTo(center.dx - radius * 0.72, center.dy + radius * 0.28)
      ..quadraticBezierTo(
        center.dx,
        center.dy + radius * 0.55,
        center.dx + radius * 0.72,
        center.dy + radius * 0.28,
      )
      ..quadraticBezierTo(
        center.dx,
        center.dy + radius * 0.72,
        center.dx - radius * 0.72,
        center.dy + radius * 0.28,
      )
      ..close();
    canvas.drawPath(band, fill);
    canvas.drawPath(band, stroke);

    final tip = Path()
      ..moveTo(center.dx + radius * 0.2, center.dy + radius * 0.48)
      ..lineTo(center.dx + radius * 0.08, center.dy + radius * 0.95)
      ..lineTo(center.dx + radius * 0.42, center.dy + radius * 0.78)
      ..close();
    canvas.drawPath(tip, fill);
    canvas.drawPath(tip, stroke);
  }

  void _paintGlasses(Canvas canvas, Offset center, double radius) {
    final r = radius * 0.28;
    final left = center.translate(-radius * 0.32, -radius * 0.08);
    final right = center.translate(radius * 0.32, -radius * 0.08);
    final lens = Paint()..color = const Color(0x331A2740);
    final rim = Paint()
      ..color = const Color(0xFF1A2740)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, radius * 0.07);
    canvas.drawCircle(left, r, lens);
    canvas.drawCircle(right, r, lens);
    canvas.drawCircle(left, r, rim);
    canvas.drawCircle(right, r, rim);
    canvas.drawLine(
      left.translate(r * 0.95, 0),
      right.translate(-r * 0.95, 0),
      rim,
    );
    canvas.drawLine(
      left.translate(-r * 0.95, -r * 0.1),
      left.translate(-r * 1.35, -r * 0.25),
      rim,
    );
    canvas.drawLine(
      right.translate(r * 0.95, -r * 0.1),
      right.translate(r * 1.35, -r * 0.25),
      rim,
    );
  }

  void _paintCape(
    Canvas canvas,
    Offset center,
    double radius, {
    required bool behind,
  }) {
    if (!behind) return;
    final fill = Paint()..color = accent.withValues(alpha: 0.92);
    final stroke = Paint()
      ..color = Color.lerp(accent, Colors.black, 0.18)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.04);
    final path = Path()
      ..moveTo(center.dx - radius * 0.15, center.dy - radius * 0.05)
      ..quadraticBezierTo(
        center.dx - radius * 1.05,
        center.dy + radius * 0.35,
        center.dx - radius * 1.05,
        center.dy + radius * 1.05,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.35,
        center.dy + radius * 0.75,
        center.dx + radius * 0.05,
        center.dy + radius * 0.45,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.05,
        center.dy + radius * 0.15,
        center.dx - radius * 0.15,
        center.dy - radius * 0.05,
      )
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _paintSparkles(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = const Color(0xFFFFC107)
      ..strokeWidth = math.max(1.4, radius * 0.05)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final angle = phase * math.pi * 2 + i * (math.pi * 2 / 5);
      final dist = radius * (1.45 + 0.12 * math.sin(phase * math.pi * 2 + i));
      final p = center.translate(
        math.cos(angle) * dist,
        math.sin(angle) * dist * 0.75 - radius * 0.1,
      );
      final arm = 2.4 + (i % 2) * 1.2;
      canvas.drawLine(p.translate(-arm, 0), p.translate(arm, 0), paint);
      canvas.drawLine(p.translate(0, -arm), p.translate(0, arm), paint);
    }
  }

  void _paintZzz(Canvas canvas, Offset center, double radius) {
    final drift = math.sin(phase * math.pi * 2) * radius * 0.06;
    final base = center.translate(radius * 0.75 + drift, -radius * 0.7);
    final style = TextPainter(
      text: TextSpan(
        text: 'z',
        style: TextStyle(
          color: colorDark.withValues(alpha: 0.55),
          fontSize: radius * 0.42,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    style.paint(canvas, base);
    final style2 = TextPainter(
      text: TextSpan(
        text: 'z',
        style: TextStyle(
          color: colorDark.withValues(alpha: 0.4),
          fontSize: radius * 0.3,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    style2.paint(
      canvas,
      base.translate(radius * 0.28, -radius * 0.35 - drift),
    );
  }

  @override
  bool shouldRepaint(covariant _PetPainter oldDelegate) {
    return oldDelegate.bob != bob ||
        oldDelegate.blink != blink ||
        oldDelegate.tilt != tilt ||
        oldDelegate.squash != squash ||
        oldDelegate.phase != phase ||
        oldDelegate.mood != mood ||
        oldDelegate.accessoryId != accessoryId ||
        oldDelegate.color != color;
  }
}
