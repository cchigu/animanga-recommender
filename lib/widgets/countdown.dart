import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 5, 4, 3, 2, 1 countdown. Each number slams in, a ring drains around it,
/// and the phone gives a small buzz on every tick.
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
    // Stronger buzz as it gets closer to 1.
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width * 0.58;
    // The closer to 1, the more intense the color.
    final intensity = 1 - (_current - 1) / max(1, widget.from - 1);
    final color = Color.lerp(widget.accent, Colors.white, 0.15 * intensity)!;

    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final v = _tick.value;
        final scale = 1.0 + 0.7 * (1 - Curves.easeOutCubic.transform(v));
        final opacity = v < 0.75 ? 1.0 : (1 - (v - 0.75) / 0.25);

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(progress: 1 - v, color: color),
              ),
              Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: Text(
                    '$_current',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.48,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: [
                        Shadow(
                          blurRadius: 30 + 30 * intensity,
                          color: color.withValues(alpha: 0.9),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
