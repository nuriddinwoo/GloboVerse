import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.glow = true});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (glow) ...[
            const Positioned(
              top: -180,
              right: -160,
              child: _Glow(size: 390, color: Color(0x398B74FF)),
            ),
            const Positioned(
              bottom: -170,
              left: -170,
              child: _Glow(size: 350, color: Color(0x244BD9EC)),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
