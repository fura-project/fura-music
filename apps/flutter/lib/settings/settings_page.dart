import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.onSettingsChanged,
    required this.onBack,
    this.embedded = false,
    super.key,
  });

  final AppSettings settings;
  final Future<AppSettingsWriteResult> Function(AppSettings settings)
  onSettingsChanged;
  final VoidCallback onBack;
  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _saving = false;

  Future<void> _save(AppSettings settings) async {
    if (_saving || settings == widget.settings) return;
    setState(() => _saving = true);
    final result = await widget.onSettingsChanged(settings);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == AppSettingsWriteResult.storageUnavailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Couldn’t save settings on this device.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolbar = AppBar(
      key: const ValueKey('settings-toolbar'),
      leading: IconButton(
        key: const ValueKey('settings-back'),
        tooltip: 'Back',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Settings'),
    );
    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            key: const ValueKey('settings-content'),
            padding: const EdgeInsets.fromLTRB(
              MusicSpacing.page,
              MusicSpacing.contentGap,
              MusicSpacing.page,
              MusicSpacing.page,
            ),
            children: [
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: MusicSpacing.itemGap),
              Text(
                'Choose how fura music follows your system appearance.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: MusicSpacing.contentGap),
              SegmentedButton<AppThemePreference>(
                key: const ValueKey('settings-theme-selector'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AppThemePreference.system,
                    icon: Icon(Icons.brightness_auto_rounded),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: {widget.settings.theme},
                onSelectionChanged: _saving
                    ? null
                    : (selection) => unawaited(
                        _save(
                          widget.settings.copyWith(theme: selection.single),
                        ),
                      ),
              ),
              const SizedBox(height: MusicSpacing.section),
              Text(
                'Playback quality',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: MusicSpacing.itemGap),
              Text(
                'This preference is used the next time a Track resolves a '
                'playable QQ Music source.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: MusicSpacing.contentGap),
              SegmentedButton<AppPlaybackQualityPreference>(
                key: const ValueKey('settings-quality-selector'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AppPlaybackQualityPreference.standard,
                    icon: Icon(Icons.music_note_rounded),
                    label: Text('Standard'),
                  ),
                  ButtonSegment(
                    value: AppPlaybackQualityPreference.high,
                    icon: Icon(Icons.high_quality_rounded),
                    label: Text('High'),
                  ),
                ],
                selected: {widget.settings.playbackQuality},
                onSelectionChanged: _saving
                    ? null
                    : (selection) => unawaited(
                        _save(
                          widget.settings.copyWith(
                            playbackQuality: selection.single,
                          ),
                        ),
                      ),
              ),
              if (_saving) ...[
                const SizedBox(height: MusicSpacing.contentGap),
                const LinearProgressIndicator(
                  key: ValueKey('settings-save-progress'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (widget.embedded) {
      return Column(
        key: const ValueKey('embedded-settings-page'),
        children: [
          SizedBox(height: kToolbarHeight, child: toolbar),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(appBar: toolbar, body: body);
  }
}
