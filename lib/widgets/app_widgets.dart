/// Small building blocks shared by the screens: the glowing page
/// background, the gradient hero card, the gradient button, letter badges
/// and labelled pills.
library;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Page background with two soft colour glows at the top.
class GlowBackground extends StatelessWidget {
  final Widget child;
  const GlowBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget glow(Alignment at, Color color, double size) => Align(
      alignment: at,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: dark ? 0.30 : 0.20),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        Positioned(
          top: -160,
          left: -120,
          child: glow(Alignment.center, AppColors.violet, 420),
        ),
        Positioned(
          top: -120,
          right: -160,
          child: glow(Alignment.center, AppColors.coral, 380),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// A rounded card filled with the dawn gradient. Text inside is white.
class HeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient gradient;
  const HeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.gradient = AppColors.dawn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white),
          child: child,
        ),
      ),
    );
  }
}

/// The main call-to-action: a pill filled with the dawn gradient.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final double height;
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: AppColors.dawn,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.orchid.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "A", "B", "C"... in a small rounded square, for answer options.
class LetterBadge extends StatelessWidget {
  final int index;
  final Color? color;
  const LetterBadge({super.key, required this.index, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        String.fromCharCode(65 + index),
        style: TextStyle(
          fontFamily: AppTheme.display,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }
}

/// A small rounded label, e.g. "Hard" or "Pharmacology".
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const Pill(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular progress ring with a percentage in the middle.
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  const ProgressRing({super.key, required this.value, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: v,
              strokeWidth: 4.5,
              strokeCap: StrokeCap.round,
              color: v >= 1 ? AppColors.mint : scheme.primary,
            ),
          ),
          Text(
            '${(v * 100).round()}',
            style: TextStyle(
              fontFamily: AppTheme.display,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
