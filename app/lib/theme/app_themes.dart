import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Available app themes
enum AppTheme {
  cyxchat,  // Original CyxChat theme - purple/indigo with cyan
  parrot,   // Classic Parrot OS - cyan/teal with green
  stealth,  // Pure dark minimal
  kali,     // Kali Linux inspired
  matrix,   // Full green terminal
  light,    // For daytime use
}

/// Theme display names
extension AppThemeExtension on AppTheme {
  String get displayName {
    switch (this) {
      case AppTheme.cyxchat:
        return 'CyxChat';
      case AppTheme.parrot:
        return 'Parrot';
      case AppTheme.stealth:
        return 'Stealth';
      case AppTheme.kali:
        return 'Kali';
      case AppTheme.matrix:
        return 'Matrix';
      case AppTheme.light:
        return 'Light';
    }
  }

  String get description {
    switch (this) {
      case AppTheme.cyxchat:
        return 'Original CyxChat theme';
      case AppTheme.parrot:
        return 'Parrot OS inspired';
      case AppTheme.stealth:
        return 'Pure dark minimal';
      case AppTheme.kali:
        return 'Kali Linux inspired';
      case AppTheme.matrix:
        return 'Terminal aesthetic';
      case AppTheme.light:
        return 'Light mode';
    }
  }
}

/// Color palettes for each theme
class ThemeColors {
  final Color primary;
  final Color accent;
  final Color background;
  final Color backgroundSecondary;
  final Color backgroundTertiary;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Brightness brightness;

  const ThemeColors({
    required this.primary,
    required this.accent,
    required this.background,
    required this.backgroundSecondary,
    required this.backgroundTertiary,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.brightness,
  });

  // Original CyxChat: purple/indigo with cyan
  static const cyxchat = ThemeColors(
    primary: Color(0xFF6C63FF),        // Purple/indigo
    accent: Color(0xFF00D9FF),         // Cyan
    background: Color(0xFF0D0D1A),     // Very dark blue
    backgroundSecondary: Color(0xFF1A1A2E),
    backgroundTertiary: Color(0xFF2D2D44),
    surface: Color(0xFF1A1A2E),
    text: Color(0xFFE8E8F0),
    textSecondary: Color(0xFF9090A0),
    success: Color(0xFF00FF88),
    warning: Color(0xFFFFBE0B),
    error: Color(0xFFFF6B9D),
    info: Color(0xFF00D9FF),
    brightness: Brightness.dark,
  );

  // Parrot OS: cyan/teal with matrix green
  static const parrot = ThemeColors(
    primary: Color(0xFF00CED1),       // Dark cyan
    accent: Color(0xFF00FF41),         // Matrix green
    background: Color(0xFF0D0D0D),     // Near black
    backgroundSecondary: Color(0xFF1A1A1A),
    backgroundTertiary: Color(0xFF2D2D2D),
    surface: Color(0xFF1A1A1A),
    text: Color(0xFFE0E0E0),
    textSecondary: Color(0xFF8B8B8B),
    success: Color(0xFF00FF41),
    warning: Color(0xFFFFBE0B),
    error: Color(0xFFFF5555),
    info: Color(0xFF00CED1),
    brightness: Brightness.dark,
  );

  // Stealth: pure dark minimal
  static const stealth = ThemeColors(
    primary: Color(0xFF6C757D),        // Gray
    accent: Color(0xFF20C997),         // Teal
    background: Color(0xFF000000),     // Pure black
    backgroundSecondary: Color(0xFF0D0D0D),
    backgroundTertiary: Color(0xFF1A1A1A),
    surface: Color(0xFF0D0D0D),
    text: Color(0xFFCCCCCC),
    textSecondary: Color(0xFF666666),
    success: Color(0xFF20C997),
    warning: Color(0xFFFFC107),
    error: Color(0xFFDC3545),
    info: Color(0xFF6C757D),
    brightness: Brightness.dark,
  );

  // Kali Linux: blue-gray with pink
  static const kali = ThemeColors(
    primary: Color(0xFF557C94),        // Blue-gray
    accent: Color(0xFFE83E8C),         // Pink
    background: Color(0xFF1A1A2E),     // Dark blue-black
    backgroundSecondary: Color(0xFF16213E),
    backgroundTertiary: Color(0xFF0F3460),
    surface: Color(0xFF16213E),
    text: Color(0xFFE8E8E8),
    textSecondary: Color(0xFF9A9AB0),
    success: Color(0xFF00D26A),
    warning: Color(0xFFFFBE0B),
    error: Color(0xFFE83E8C),
    info: Color(0xFF557C94),
    brightness: Brightness.dark,
  );

  // Matrix: full green terminal
  static const matrix = ThemeColors(
    primary: Color(0xFF00FF00),        // Lime green
    accent: Color(0xFF39FF14),         // Neon green
    background: Color(0xFF0D0208),     // Dark green-black
    backgroundSecondary: Color(0xFF0A1A0A),
    backgroundTertiary: Color(0xFF0F2A0F),
    surface: Color(0xFF0A1A0A),
    text: Color(0xFF00FF00),
    textSecondary: Color(0xFF00AA00),
    success: Color(0xFF39FF14),
    warning: Color(0xFFCCFF00),
    error: Color(0xFFFF3300),
    info: Color(0xFF00FF00),
    brightness: Brightness.dark,
  );

  // Light theme
  static const light = ThemeColors(
    primary: Color(0xFF0077B6),        // Blue
    accent: Color(0xFF00B4D8),         // Cyan
    background: Color(0xFFF8F9FA),     // Light gray
    backgroundSecondary: Color(0xFFFFFFFF),
    backgroundTertiary: Color(0xFFE9ECEF),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF212529),
    textSecondary: Color(0xFF6C757D),
    success: Color(0xFF198754),
    warning: Color(0xFFFFC107),
    error: Color(0xFFDC3545),
    info: Color(0xFF0077B6),
    brightness: Brightness.light,
  );

  static ThemeColors fromTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.cyxchat:
        return cyxchat;
      case AppTheme.parrot:
        return parrot;
      case AppTheme.stealth:
        return stealth;
      case AppTheme.kali:
        return kali;
      case AppTheme.matrix:
        return matrix;
      case AppTheme.light:
        return light;
    }
  }
}

/// App theme builder
class AppThemes {
  static ThemeData getThemeData(AppTheme theme, {String? fontFamily}) {
    final colors = ThemeColors.fromTheme(theme);
    return _buildThemeData(colors, fontFamily: fontFamily);
  }

  static ThemeData _buildThemeData(ThemeColors colors, {String? fontFamily}) {
    final isDark = colors.brightness == Brightness.dark;

    return ThemeData(
      brightness: colors.brightness,
      useMaterial3: true,
      fontFamily: fontFamily,
      primaryColor: colors.primary,
      scaffoldBackgroundColor: colors.background,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: colors.primary,
              secondary: colors.accent,
              surface: colors.surface,
              error: colors.error,
              onPrimary: _contrastColor(colors.primary),
              onSecondary: _contrastColor(colors.accent),
              onSurface: colors.text,
              onError: Colors.white,
              primaryContainer: colors.backgroundTertiary,
              onPrimaryContainer: colors.text,
              secondaryContainer: colors.backgroundTertiary,
              onSecondaryContainer: colors.text,
              // Surface container hierarchy (from lightest to darkest in dark mode)
              surfaceContainerLowest: colors.background,
              surfaceContainerLow: colors.surface,
              surfaceContainer: colors.backgroundSecondary,
              surfaceContainerHigh: colors.backgroundTertiary,
              surfaceContainerHighest: colors.backgroundTertiary,
              outline: colors.backgroundTertiary,
              outlineVariant: colors.backgroundTertiary.withOpacity(0.5),
            )
          : ColorScheme.light(
              primary: colors.primary,
              secondary: colors.accent,
              surface: colors.surface,
              error: colors.error,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: colors.text,
              onError: Colors.white,
              primaryContainer: colors.backgroundTertiary,
              onPrimaryContainer: colors.text,
              // Surface container hierarchy (from darkest to lightest in light mode)
              surfaceContainerLowest: colors.background,
              surfaceContainerLow: colors.surface,
              surfaceContainer: colors.backgroundSecondary,
              surfaceContainerHigh: colors.backgroundTertiary,
              surfaceContainerHighest: colors.backgroundTertiary,
              outline: colors.backgroundTertiary,
              outlineVariant: colors.backgroundTertiary.withOpacity(0.5),
            ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.background,
        foregroundColor: colors.text,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: colors.text),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark ? BorderSide.none : BorderSide(color: colors.backgroundTertiary),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        tileColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        textColor: colors.text,
        iconColor: colors.textSecondary,
      ),
      dividerTheme: DividerThemeData(
        color: colors.backgroundTertiary,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.backgroundSecondary,
        hintStyle: TextStyle(color: colors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.backgroundTertiary, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.error, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: _contrastColor(colors.primary),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: _contrastColor(colors.primary),
        elevation: 4,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.backgroundSecondary,
        indicatorColor: colors.primary.withOpacity(0.2),
        elevation: 0,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            );
          }
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.primary, size: 24);
          }
          return IconThemeData(color: colors.textSecondary, size: 24);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.backgroundTertiary,
        labelStyle: TextStyle(color: colors.text, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.backgroundTertiary,
        contentTextStyle: TextStyle(color: colors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.backgroundSecondary,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.textSecondary,
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.backgroundSecondary,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.backgroundSecondary,
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary.withOpacity(0.5);
          }
          return colors.backgroundTertiary;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.backgroundTertiary,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withOpacity(0.2),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: colors.text,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: colors.text,
          letterSpacing: -0.5,
        ),
        headlineSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.text,
        ),
        titleSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          color: colors.text,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: colors.text,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          color: colors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        labelMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Get contrasting text color for background
  static Color _contrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// Get theme colors for use in custom widgets
  static ThemeColors getColors(AppTheme theme) {
    return ThemeColors.fromTheme(theme);
  }
}

/// Available font families
enum AppFont {
  system,
  robotoMono,
  firaCode,
  jetbrainsMono,
  sourceCodePro,
}

extension AppFontExtension on AppFont {
  String get displayName {
    switch (this) {
      case AppFont.system:
        return 'System Default';
      case AppFont.robotoMono:
        return 'Roboto Mono';
      case AppFont.firaCode:
        return 'Fira Code';
      case AppFont.jetbrainsMono:
        return 'JetBrains Mono';
      case AppFont.sourceCodePro:
        return 'Source Code Pro';
    }
  }

  /// Returns the font family name for use in ThemeData
  String? get fontFamily {
    switch (this) {
      case AppFont.system:
        return null;
      case AppFont.robotoMono:
        return GoogleFonts.robotoMono().fontFamily;
      case AppFont.firaCode:
        return GoogleFonts.firaCode().fontFamily;
      case AppFont.jetbrainsMono:
        return GoogleFonts.jetBrainsMono().fontFamily;
      case AppFont.sourceCodePro:
        return GoogleFonts.sourceCodePro().fontFamily;
    }
  }

  /// Get TextTheme with this font applied (for google_fonts)
  TextTheme getTextTheme(TextTheme base) {
    switch (this) {
      case AppFont.system:
        return base;
      case AppFont.robotoMono:
        return GoogleFonts.robotoMonoTextTheme(base);
      case AppFont.firaCode:
        return GoogleFonts.firaCodeTextTheme(base);
      case AppFont.jetbrainsMono:
        return GoogleFonts.jetBrainsMonoTextTheme(base);
      case AppFont.sourceCodePro:
        return GoogleFonts.sourceCodeProTextTheme(base);
    }
  }
}

/// Font scale options
enum FontScale {
  small,
  medium,
  large,
  extraLarge,
}

extension FontScaleExtension on FontScale {
  String get displayName {
    switch (this) {
      case FontScale.small:
        return 'S';
      case FontScale.medium:
        return 'M';
      case FontScale.large:
        return 'L';
      case FontScale.extraLarge:
        return 'XL';
    }
  }

  double get factor {
    switch (this) {
      case FontScale.small:
        return 0.85;
      case FontScale.medium:
        return 1.0;
      case FontScale.large:
        return 1.15;
      case FontScale.extraLarge:
        return 1.3;
    }
  }
}

/// Wallpaper type
enum WallpaperType {
  none,
  solid,
  pattern,
  image,
}

/// Built-in patterns
enum WallpaperPattern {
  circuit,
  matrix,
  hex,
  binary,
  terminal,
}

extension WallpaperPatternExtension on WallpaperPattern {
  String get displayName {
    switch (this) {
      case WallpaperPattern.circuit:
        return 'Circuit';
      case WallpaperPattern.matrix:
        return 'Matrix';
      case WallpaperPattern.hex:
        return 'Honeycomb';
      case WallpaperPattern.binary:
        return 'Binary';
      case WallpaperPattern.terminal:
        return 'Terminal';
    }
  }
}
