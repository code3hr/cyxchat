import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_themes.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(
                Icons.palette_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Appearance'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Theme section
            _SectionHeader(
              icon: Icons.color_lens_rounded,
              title: 'THEME',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),
            _ThemeSelector(settings: settings),
            const SizedBox(height: 24),

            // Font section
            _SectionHeader(
              icon: Icons.text_fields_rounded,
              title: 'FONT',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),
            _FontFamilySelector(settings: settings),
            const SizedBox(height: 16),
            _FontScaleSelector(settings: settings),
            const SizedBox(height: 24),

            // Chat background section
            _SectionHeader(
              icon: Icons.wallpaper_rounded,
              title: 'CHAT BACKGROUND',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),
            _WallpaperSelector(settings: settings),
            const SizedBox(height: 24),

            // Message bubbles section
            _SectionHeader(
              icon: Icons.chat_bubble_rounded,
              title: 'MESSAGE BUBBLES',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),
            _BubbleRadiusSelector(settings: settings),
            const SizedBox(height: 24),

            // Chat list section
            _SectionHeader(
              icon: Icons.list_rounded,
              title: 'CHAT LIST',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),
            _MessagePreviewToggle(settings: settings),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme colorScheme;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

class _ThemeSelector extends ConsumerWidget {
  final AppSettings settings;

  const _ThemeSelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: AppTheme.values.map((appTheme) {
              final isSelected = settings.theme == appTheme;
              final themeColors = ThemeColors.fromTheme(appTheme);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    ref.read(settingsProvider.notifier).setTheme(appTheme);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: themeColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: themeColors.primary, width: 2)
                                : Border.all(color: themeColors.backgroundTertiary),
                          ),
                          child: Stack(
                            children: [
                              // Preview elements
                              Positioned(
                                top: 8,
                                left: 8,
                                right: 8,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: themeColors.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 20,
                                left: 8,
                                child: Container(
                                  width: 20,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: themeColors.backgroundSecondary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 20,
                                right: 8,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: themeColors.accent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                right: 8,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: themeColors.textSecondary.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              // Checkmark
                              if (isSelected)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: themeColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          appTheme.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Current theme description
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.primary.withOpacity(0.8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    settings.theme.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FontFamilySelector extends ConsumerWidget {
  final AppSettings settings;

  const _FontFamilySelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Font Family',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: AppFont.values.map((font) {
                final isSelected = settings.fontFamily == font;
                return InkWell(
                  onTap: () {
                    ref.read(settingsProvider.notifier).setFontFamily(font);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            font.displayName,
                            style: TextStyle(
                              fontFamily: font.fontFamily,
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontScaleSelector extends ConsumerWidget {
  final AppSettings settings;

  const _FontScaleSelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Font Size',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                settings.fontScale.displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: FontScale.values.map((scale) {
              final isSelected = settings.fontScale == scale;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    ref.read(settingsProvider.notifier).setFontScale(scale);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withOpacity(0.2)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: colorScheme.primary.withOpacity(0.5))
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        scale.displayName,
                        style: TextStyle(
                          fontSize: 14 * scale.factor,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Preview text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Preview text at ${(settings.fontScale.factor * 100).toInt()}% scale',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WallpaperSelector extends ConsumerWidget {
  final AppSettings settings;

  const _WallpaperSelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Parse current wallpaper
    final wallpaper = settings.chatWallpaper;
    final isNone = wallpaper == null;
    final isSolid = wallpaper?.startsWith('solid:') ?? false;
    final isPattern = wallpaper?.startsWith('pattern:') ?? false;
    final isImage = wallpaper?.startsWith('file:') ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type selector
          Row(
            children: [
              _WallpaperTypeButton(
                icon: Icons.block_rounded,
                label: 'None',
                isSelected: isNone,
                onTap: () {
                  ref.read(settingsProvider.notifier).setChatWallpaper(null);
                },
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _WallpaperTypeButton(
                icon: Icons.format_color_fill_rounded,
                label: 'Solid',
                isSelected: isSolid,
                onTap: () => _showSolidColorPicker(context, ref, colorScheme),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _WallpaperTypeButton(
                icon: Icons.grid_4x4_rounded,
                label: 'Pattern',
                isSelected: isPattern,
                onTap: () => _showPatternPicker(context, ref, colorScheme),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _WallpaperTypeButton(
                icon: Icons.image_rounded,
                label: 'Image',
                isSelected: isImage,
                onTap: () => _pickImage(context, ref),
                colorScheme: colorScheme,
              ),
            ],
          ),
          if (wallpaper != null) ...[
            const SizedBox(height: 12),
            // Preview
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _getPreviewColor(wallpaper, colorScheme),
                borderRadius: BorderRadius.circular(12),
                image: isImage ? _getImageDecoration(wallpaper) : null,
              ),
              child: isPattern
                  ? _PatternPreview(pattern: wallpaper.replaceFirst('pattern:', ''))
                  : null,
            ),
            const SizedBox(height: 8),
            // Clear button
            TextButton.icon(
              onPressed: () {
                ref.read(settingsProvider.notifier).setChatWallpaper(null);
              },
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear wallpaper'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getPreviewColor(String wallpaper, ColorScheme colorScheme) {
    if (wallpaper.startsWith('solid:')) {
      final hex = wallpaper.replaceFirst('solid:', '');
      try {
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {
        return colorScheme.surfaceContainerHighest;
      }
    }
    return colorScheme.surfaceContainerHighest;
  }

  DecorationImage? _getImageDecoration(String wallpaper) {
    if (!wallpaper.startsWith('file:')) return null;
    final path = wallpaper.replaceFirst('file:', '');
    final file = File(path);
    if (!file.existsSync()) return null;
    return DecorationImage(
      image: FileImage(file),
      fit: BoxFit.cover,
    );
  }

  void _showSolidColorPicker(BuildContext context, WidgetRef ref, ColorScheme colorScheme) {
    final colors = [
      '#1A1A2E', '#16213E', '#0F3460', '#1A1A1A', '#0D0D0D',
      '#2D2D2D', '#1E3A5F', '#0A1A0A', '#1A0A1A', '#0A1A1A',
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose Color',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((hex) {
                final color = Color(int.parse(hex.replaceFirst('#', '0xFF')));
                return GestureDetector(
                  onTap: () {
                    ref.read(settingsProvider.notifier).setChatWallpaper('solid:$hex');
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outline),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showPatternPicker(BuildContext context, WidgetRef ref, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose Pattern',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: WallpaperPattern.values.map((pattern) {
                return GestureDetector(
                  onTap: () {
                    ref.read(settingsProvider.notifier).setChatWallpaper('pattern:${pattern.name}');
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outline),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PatternPreview(pattern: pattern.name, size: 40),
                        const SizedBox(height: 4),
                        Text(
                          pattern.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        // Copy to app documents directory for persistence
        final appDir = await getApplicationDocumentsDirectory();
        final wallpaperDir = Directory('${appDir.path}/wallpapers');
        if (!await wallpaperDir.exists()) {
          await wallpaperDir.create(recursive: true);
        }
        final destPath = '${wallpaperDir.path}/${file.name}';
        await File(file.path!).copy(destPath);

        ref.read(settingsProvider.notifier).setChatWallpaper('file:$destPath');
      }
    }
  }
}

class _WallpaperTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _WallpaperTypeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.2)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: colorScheme.primary.withOpacity(0.5))
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatternPreview extends StatelessWidget {
  final String pattern;
  final double size;

  const _PatternPreview({required this.pattern, this.size = 100});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    IconData icon;
    switch (pattern) {
      case 'circuit':
        icon = Icons.developer_board_rounded;
        break;
      case 'matrix':
        icon = Icons.blur_on_rounded;
        break;
      case 'hex':
        icon = Icons.hexagon_rounded;
        break;
      case 'binary':
        icon = Icons.code_rounded;
        break;
      case 'terminal':
        icon = Icons.terminal_rounded;
        break;
      default:
        icon = Icons.grid_4x4_rounded;
    }

    return Center(
      child: Icon(
        icon,
        size: size * 0.4,
        color: colorScheme.primary.withOpacity(0.5),
      ),
    );
  }
}

class _BubbleRadiusSelector extends ConsumerWidget {
  final AppSettings settings;

  const _BubbleRadiusSelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Corner Radius',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                '${settings.bubbleRadius.toInt()}px',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: settings.bubbleRadius,
              min: 0,
              max: 24,
              divisions: 6,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setBubbleRadius(value);
              },
            ),
          ),
          const SizedBox(height: 16),
          // Preview bubbles
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(settings.bubbleRadius),
                      topRight: Radius.circular(settings.bubbleRadius),
                      bottomLeft: Radius.circular(settings.bubbleRadius),
                      bottomRight: const Radius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Preview message',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(settings.bubbleRadius),
                      topRight: Radius.circular(settings.bubbleRadius),
                      bottomLeft: const Radius.circular(4),
                      bottomRight: Radius.circular(settings.bubbleRadius),
                    ),
                  ),
                  child: Text(
                    'Reply message',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessagePreviewToggle extends ConsumerWidget {
  final AppSettings settings;

  const _MessagePreviewToggle({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.preview_rounded,
              size: 20,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Show message preview',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Display message text in chat list',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: settings.showMessagePreview,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setShowMessagePreview(value);
            },
          ),
        ],
      ),
    );
  }
}
