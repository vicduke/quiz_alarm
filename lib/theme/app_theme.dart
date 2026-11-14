/// The app's look: colours, fonts and the styling of every standard
/// component (cards, buttons, inputs, sheets, navigation). Screens take
/// their style from here, so change the look in this one place.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class AppColors {
  // The "dawn" gradient used for hero cards and primary actions.
  static const Color violet = Color(0xFF7C5CFF);
  static const Color orchid = Color(0xFFC86BFA);
  static const Color coral = Color(0xFFFF8F6B);
  static const Color amber = Color(0xFFFFB86B);
  static const Color mint = Color(0xFF3DDC97);
  static const Color rose = Color(0xFFFF6B81);

  static const LinearGradient dawn = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, orchid, coral],
  );

  static const LinearGradient night = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A1F6B), Color(0xFF4B2C8F), Color(0xFF8A3F8F)],
  );
}

class AppTheme {
  static const String display = 'Outfit';
  static const String body = 'PlusJakartaSans';

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: const Color(0xFF0B0B14),
    surface: const Color(0xFF151524),
    surfaceHigh: const Color(0xFF1E1E32),
    outline: const Color(0xFF2E2E48),
    primary: const Color(0xFF9D8CFF),
    onPrimary: const Color(0xFF14102E),
    text: const Color(0xFFF2F1FA),
    muted: const Color(0xFFA5A3BD),
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: const Color(0xFFF5F4FB),
    surface: Colors.white,
    surfaceHigh: const Color(0xFFECEAF8),
    outline: const Color(0xFFDDDAEE),
    primary: const Color(0xFF5B45E0),
    onPrimary: Colors.white,
    text: const Color(0xFF17152B),
    muted: const Color(0xFF65627F),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color outline,
    required Color primary,
    required Color onPrimary,
    required Color text,
    required Color muted,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.violet,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          secondary: isDark ? AppColors.amber : const Color(0xFFD9652B),
          tertiary: AppColors.mint,
          error: isDark ? AppColors.rose : const Color(0xFFD23B55),
          surface: background,
          onSurface: text,
          onSurfaceVariant: muted,
          surfaceContainerLowest: background,
          surfaceContainerLow: surface,
          surfaceContainer: surface,
          surfaceContainerHigh: surfaceHigh,
          surfaceContainerHighest: surfaceHigh,
          outline: outline,
          outlineVariant: outline,
          secondaryContainer: primary.withValues(alpha: isDark ? 0.22 : 0.14),
          onSecondaryContainer: text,
        );

    final base = ThemeData(
      colorScheme: scheme,
      fontFamily: body,
      scaffoldBackgroundColor: background,
    );
    TextStyle? heading(TextStyle? s, {FontWeight weight = FontWeight.w600}) =>
        s?.copyWith(fontFamily: display, fontWeight: weight, color: text);
    final textTheme = base.textTheme.copyWith(
      displayLarge: heading(base.textTheme.displayLarge),
      displayMedium: heading(base.textTheme.displayMedium),
      displaySmall: heading(base.textTheme.displaySmall),
      headlineLarge: heading(base.textTheme.headlineLarge),
      headlineMedium: heading(base.textTheme.headlineMedium),
      headlineSmall: heading(base.textTheme.headlineSmall),
      titleLarge: heading(base.textTheme.titleLarge),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(color: muted),
      labelSmall: base.textTheme.labelSmall?.copyWith(color: muted),
    );

    const pill = StadiumBorder();
    final rounded16 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: text,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: display,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          minimumSize: const Size(64, 50),
          textStyle: const TextStyle(
            fontFamily: body,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: outline, width: 1.5),
          foregroundColor: text,
          textStyle: const TextStyle(
            fontFamily: body,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide(color: outline),
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: isDark ? 0.28 : 0.16),
        checkmarkColor: primary,
        labelStyle: TextStyle(
          fontFamily: body,
          color: text,
          fontWeight: FontWeight.w600,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: outline),
          selectedBackgroundColor: primary.withValues(
            alpha: isDark ? 0.28 : 0.16,
          ),
          selectedForegroundColor: text,
          foregroundColor: muted,
          textStyle: const TextStyle(
            fontFamily: body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: primary.withValues(alpha: isDark ? 0.26 : 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: body,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? text : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
          fontFamily: display,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2A44) : text,
        contentTextStyle: TextStyle(
          fontFamily: body,
          color: isDark ? text : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: rounded16,
      ),
      listTileTheme: ListTileThemeData(iconColor: muted, textColor: text),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: outline,
        circularTrackColor: outline,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        shape: pill,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: outline,
      ),
    );
  }
}
