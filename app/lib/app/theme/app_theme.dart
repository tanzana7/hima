import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Material 3 base with the hima. tokens applied so the app does not read as
/// stock Material: pill buttons, soft rounded sheets and purple-tinted ink.
ThemeData buildHimaTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.purple,
    onPrimary: Colors.white,
    primaryContainer: AppColors.purpleSoft,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.coral,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.peachSoft,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.lime,
    onTertiary: AppColors.ink,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.muted,
    outlineVariant: AppColors.purpleSoft,
    error: AppColors.danger,
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamilyFallback: const ['Noto Sans JP', 'Hiragino Sans', 'Yu Gothic'],
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .copyWith(
          headlineLarge: AppTextStyles.heroTitle,
          headlineMedium: AppTextStyles.heroTitle.copyWith(fontSize: 28),
          titleLarge: AppTextStyles.sectionTitle,
          titleMedium: AppTextStyles.friendName.copyWith(fontSize: 16),
          bodyLarge: AppTextStyles.body.copyWith(fontSize: 16),
          bodyMedium: AppTextStyles.body,
          bodySmall: AppTextStyles.caption,
          labelLarge: AppTextStyles.button.copyWith(fontSize: 16),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.sectionTitle,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        textStyle: AppTextStyles.button.copyWith(fontSize: 17),
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s24,
          vertical: AppSpacing.s12,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: AppTextStyles.button.copyWith(fontSize: 16),
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        side: const BorderSide(
          color: AppColors.purple,
          width: AppSpacing.borderWidth,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.purple,
        textStyle: AppTextStyles.button.copyWith(fontSize: 15),
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(
          AppSpacing.minTapTarget,
          AppSpacing.minTapTarget,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppTextStyles.body.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusHero),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.purpleSoft.withValues(alpha: 0.45),
      hintStyle: AppTextStyles.body.copyWith(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        borderSide: const BorderSide(
          color: AppColors.purple,
          width: AppSpacing.borderWidth,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.purpleSoft,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.purple
            : AppColors.purpleSoft,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.purple,
    ),
  );
}
