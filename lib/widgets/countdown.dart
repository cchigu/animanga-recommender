import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 5, 4, 3, 2, 1 countdown drawn as a clock face. Each second the hand
/// sweeps one full turn from 12 o'clock, leaving a glowing wedge behind it.
/// Numbers grow as the countdown approaches 1, and the phone buzzes harder.
class Countdown extends StatefulWidget {
  final int from;
  final Color accent;
  final VoidCallback onFinished;

  const Countdown({
    super.key,
    this.from = 5,
    required this.accent,
    required this.onFinished,
  });

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown>
    with SingleTickerProviderStateMixin {
  /// Number height as a fraction of the clock size, for the first number (5)
  /// and the last number (1). Swap these two values to make it shrink instead.
  static const double _firstNumberSize = 0.22;
  static const double _lastNumberSize = 0.50;

  late int _current = widget.from;
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    _tick.addStatusListener(_onStatus);
    _startTick();
  }

  void _startTick() {
    if (_current <= 1) {
      HapticFeedback.heavyImpact();
    } else if (_current <= 3) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    _tick.forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_current > 1) {
      setState(() => _current--);
      _startTick();
    } else {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  /// 0 for the first number shown, 1 for the last one.
  double get _progress =>
      widget.from <= 1 ? 1 : (widget.from - _current) / (widget.from - 1);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width * 0.66;
    final color =
        Color.lerp(widget.accent, Colors.white, 0.2 * _progress)!;
    final numberSize = size *
        (_firstNumberSize + (_lastNumberSize - _firstNumberSize) * _progress);

    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final v = _tick.value;
        // Each number pops in slightly oversized, then settles.
        final pop = 1.0 + 0.25 * (1 - Curves.easeOutBack.transform(min(1.0, v * 2.5)));
        final opacity = v < 0.85 ? 1.0 : (1 - (v - 0.85) / 0.15);

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _ClockPainter(sweep: v, color: color, hand: false),
              ),
              Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: pop,
                  child: Text(
                    '$_current',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: numberSize,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: [
                        Shadow(
                          blurRadius: 20 + 30 * _progress,
                          color: color.withValues(alpha: 0.9),
                        ),
                        const Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ),
              // The hand sweeps over the number, capped at the center.
              CustomPaint(
                size: Size.square(size),
                painter: _ClockPainter(sweep: v, color: color, hand: true),
              ),
              Container(
                width: size * 0.05,
                height: size * 0.05,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: color, blurRadius: 10, spreadRadius: 1),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Clock face: outer rim, 60 minute ticks (every 5th one long), a wedge that
/// fills behind the hand, and the hand itself sweeping from 12 o'clock.
class _ClockPainter extends CustomPainter {
  final double sweep; // 0..1, one full turn per second
  final Color color;
  final bool hand; // false = face layer, true = hand layer

  _ClockPainter({
    required this.sweep,
    required this.color,
    required this.hand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    const top = -pi / 2;
    final angle = top + 2 * pi * sweep;

    if (hand) {
      _paintHand(canvas, center, radius, angle);
      return;
    }

    // Face
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    // Swept wedge behind the hand
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.92),
      top,
      2 * pi * sweep,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * pi,
          transform: const GradientRotation(top),
          colors: [
            color.withValues(alpha: 0.02),
            color.withValues(alpha: 0.35),
          ],
          stops: [0, max(0.001, sweep)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // Rim
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color,
    );

    // Minute ticks
    final minor = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.35);
    final major = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 60; i++) {
      final isMajor = i % 5 == 0;
      final a = top + 2 * pi * i / 60;
      final dir = Offset(cos(a), sin(a));
      final outer = radius - 10;
      final inner = outer - (isMajor ? radius * 0.11 : radius * 0.05);
      canvas.drawLine(
        center + dir * inner,
        center + dir * outer,
        isMajor ? major : minor,
      );
    }
  }

  // Hand, with a short tail past the center like a real clock
  void _paintHand(Canvas canvas, Offset center, double radius, double angle) {
    final dir = Offset(cos(angle), sin(angle));
    final handPaint = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawLine(
      center - dir * radius * 0.14,
      center + dir * radius * 0.86,
      Paint()
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      center - dir * radius * 0.14,
      center + dir * radius * 0.86,
      handPaint,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.sweep != sweep || old.color != color || old.hand != hand;
}
