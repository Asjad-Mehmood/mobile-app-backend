import 'package:flutter/material.dart';

/// Brand colours that don't map onto a Material role.
@immutable
class BakeryColors extends ThemeExtension<BakeryColors> {
  const BakeryColors({required this.cardBorder, required this.success, required this.warning, required this.waxSeal, required this.crumb});

  final Color cardBorder;
  final Color success;
  final Color warning;
  final Color waxSeal;
  final Color crumb;

  static const light = BakeryColors(
    cardBorder: Color(0xFFE8D8C8),
    success: Color(0xFF4E6E58),
    warning: Color(0xFFB7791F),
    waxSeal: Color(0xFFA4161A),
    crumb: Color(0xFFD4A373),
  );
  static const dark = BakeryColors(
    cardBorder: Color(0xFF4A3A33),
    success: Color(0xFF7FA68B),
    warning: Color(0xFFE6B566),
    waxSeal: Color(0xFFE5484D),
    crumb: Color(0xFFE6C29F),
  );

  @override
  BakeryColors copyWith({Color? cardBorder, Color? success, Color? warning, Color? waxSeal, Color? crumb}) => BakeryColors(
        cardBorder: cardBorder ?? this.cardBorder,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        waxSeal: waxSeal ?? this.waxSeal,
        crumb: crumb ?? this.crumb,
      );

  @override
  BakeryColors lerp(BakeryColors? other, double t) => other == null
      ? this
      : BakeryColors(
          cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          waxSeal: Color.lerp(waxSeal, other.waxSeal, t)!,
          crumb: Color.lerp(crumb, other.crumb, t)!,
        );
}

extension BakeryThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  BakeryColors get bakery => Theme.of(this).extension<BakeryColors>() ?? BakeryColors.light;

  void toast(String message, {bool error = false}) {
    final m = ScaffoldMessenger.maybeOf(this);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? colors.error : null,
    ));
  }
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF8C4A27),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFDBCB),
  onPrimaryContainer: Color(0xFF341100),
  secondary: Color(0xFFD4A373),
  onSecondary: Color(0xFF3B2410),
  secondaryContainer: Color(0xFFF5E1C8),
  onSecondaryContainer: Color(0xFF3B2410),
  tertiary: Color(0xFF4E6E58),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFD0EAD6),
  onTertiaryContainer: Color(0xFF0B2015),
  error: Color(0xFFC84B31),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD3),
  onErrorContainer: Color(0xFF410000),
  surface: Color(0xFFFFFDF9),
  onSurface: Color(0xFF2A1F1B),
  surfaceDim: Color(0xFFE4D8CB),
  surfaceBright: Color(0xFFFFFDF9),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFBF5EE),
  surfaceContainer: Color(0xFFF7EFE5),
  surfaceContainerHigh: Color(0xFFF2E8DC),
  surfaceContainerHighest: Color(0xFFECE0D3),
  onSurfaceVariant: Color(0xFF52443C),
  outline: Color(0xFF85736A),
  outlineVariant: Color(0xFFE8D8C8),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF3B2E28),
  onInverseSurface: Color(0xFFFBEEE6),
  inversePrimary: Color(0xFFFFB690),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFFB690),
  onPrimary: Color(0xFF552000),
  primaryContainer: Color(0xFF6F3416),
  onPrimaryContainer: Color(0xFFFFDBCB),
  secondary: Color(0xFFE6C29F),
  onSecondary: Color(0xFF422C15),
  secondaryContainer: Color(0xFF5A4129),
  onSecondaryContainer: Color(0xFFFFDDB8),
  tertiary: Color(0xFF7FA68B),
  onTertiary: Color(0xFF0F2A1A),
  tertiaryContainer: Color(0xFF365541),
  onTertiaryContainer: Color(0xFFD0EAD6),
  error: Color(0xFFFF897D),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF1C1411),
  onSurface: Color(0xFFEFE0D8),
  surfaceDim: Color(0xFF1C1411),
  surfaceBright: Color(0xFF433631),
  surfaceContainerLowest: Color(0xFF17100D),
  surfaceContainerLow: Color(0xFF231915),
  surfaceContainer: Color(0xFF2A1F1B),
  surfaceContainerHigh: Color(0xFF352A25),
  surfaceContainerHighest: Color(0xFF40342F),
  onSurfaceVariant: Color(0xFFD7C2B8),
  outline: Color(0xFFA08D83),
  outlineVariant: Color(0xFF4A3A33),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFEFE0D8),
  onInverseSurface: Color(0xFF3B2E28),
  inversePrimary: Color(0xFF8C4A27),
);

const _serif = 'PlayfairDisplay';
const _sans = 'PlusJakartaSans';
const _pkg = 'crumb_core';

TextStyle _s(String family, double size, FontWeight w, {double? height, double spacing = 0}) => TextStyle(
      fontFamily: family,
      package: _pkg,
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation.weight(w.value.toDouble())],
      height: height,
      letterSpacing: spacing,
    );

TextTheme _textTheme(Color onSurface) => TextTheme(
      displayLarge: _s(_serif, 48, FontWeight.w700, height: 1.1),
      displayMedium: _s(_serif, 40, FontWeight.w700, height: 1.1),
      displaySmall: _s(_serif, 32, FontWeight.w700, height: 1.15),
      headlineLarge: _s(_serif, 30, FontWeight.w700, height: 1.2),
      headlineMedium: _s(_serif, 26, FontWeight.w700, height: 1.2),
      headlineSmall: _s(_serif, 22, FontWeight.w600, height: 1.25),
      titleLarge: _s(_serif, 20, FontWeight.w600, height: 1.3),
      titleMedium: _s(_sans, 16, FontWeight.w700, height: 1.35),
      titleSmall: _s(_sans, 14, FontWeight.w700, height: 1.35),
      bodyLarge: _s(_sans, 16, FontWeight.w400, height: 1.5),
      bodyMedium: _s(_sans, 14, FontWeight.w400, height: 1.45),
      bodySmall: _s(_sans, 12, FontWeight.w400, height: 1.4),
      labelLarge: _s(_sans, 14, FontWeight.w700, spacing: 0.2),
      labelMedium: _s(_sans, 12, FontWeight.w600, spacing: 0.3),
      labelSmall: _s(_sans, 11, FontWeight.w600, spacing: 0.4),
    ).apply(bodyColor: onSurface, displayColor: onSurface);

ThemeData _build(ColorScheme c, BakeryColors b) {
  final text = _textTheme(c.onSurface);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    colorScheme: c,
    scaffoldBackgroundColor: c.surface,
    textTheme: text,
    fontFamily: _sans,
    extensions: [b],
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: b.cardBorder)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: shape, textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), shape: shape, textStyle: text.labelLarge, side: BorderSide(color: c.outline)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: b.cardBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: b.cardBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: b.cardBorder),
      labelStyle: text.labelMedium,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surfaceContainerLow,
      indicatorColor: c.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: c.surfaceContainerLow, indicatorColor: c.primaryContainer),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent, showDragHandle: true),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: b.cardBorder, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

final ThemeData bakeryLightTheme = _build(_lightScheme, BakeryColors.light);
final ThemeData bakeryDarkTheme = _build(_darkScheme, BakeryColors.dark);
