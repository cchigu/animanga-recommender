import 'package:flutter/material.dart';

/// The big glowing "Tap here" circle with a slow breathing pulse.
class TapCircle extends StatefulWidget {
  final Color accent;
  final VoidCallback onTap;
  final String label;

  const TapCircle({
    super.key,
    required this.accent,
    required this.onTap,
    this.label = 'Tap here',
  });

  @override
  State<TapCircle> createState() => _TapCircleState();
}

class _TapCircleState extends State<TapCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  bool _pressed = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width * 0.58;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Transform.scale(
            scale: 1.0 + 0.045 * t,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color.lerp(widget.accent, Colors.white, 0.25)!,
                    widget.accent,
                    Color.lerp(widget.accent, Colors.black, 0.35)!,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                  center: const Alignment(-0.3, -0.35),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.accent.withValues(alpha: 0.35 + 0.3 * t),
                    blurRadius: 40 + 30 * t,
                    spreadRadius: 4 + 8 * t,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: child,
            ),
          );
        },
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            shadows: [Shadow(blurRadius: 8, color: Colors.black38)],
          ),
        ),
      ),
      ),
    );
  }
}
