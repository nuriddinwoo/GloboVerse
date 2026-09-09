import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.showWordmark = false});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlobePainter()),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text(
          'GloboVerse',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}

class _GlobePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Offset.zero & size;
    final fill = Paint()
      ..shader = AppColors.heroGradient.createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fill);

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.038)
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: radius * 1.02, height: radius * 1.72),
      line,
    );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radius * 1.7, height: radius * 0.76),
      line,
    );
    canvas.drawCircle(center, radius * 0.76, line..color = Colors.white.withValues(alpha: 0.22));

    final orbit = Paint()
      ..color = AppColors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.width * 0.046)
      ..strokeCap = StrokeCap.round;
    final orbitRect = Rect.fromCenter(
      center: center.translate(0, radius * 0.02),
      width: radius * 2.18,
      height: radius * 0.72,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.35);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(orbitRect, -0.1, math.pi * 0.82, false, orbit);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
