import 'package:flutter/material.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

const _qqGreen = Color(0xFF24B86A);

class MusicApp extends StatelessWidget {
  const MusicApp({required this.bootstrap, super.key});

  final BootstrapStatus bootstrap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutterust Music',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: BootstrapPage(bootstrap: bootstrap),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _qqGreen,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }
}

class BootstrapPage extends StatelessWidget {
  const BootstrapPage({required this.bootstrap, super.key});

  final BootstrapStatus bootstrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = bootstrap.provider;

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.12),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusLabel(providerName: provider.displayName),
                  const SizedBox(height: 32),
                  Text(
                    'Your QQ Music library,\nwithout the browser frame.',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.06,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'The in-process Rust core is connected. Authentication is '
                    'the next product slice; no account capability is exposed '
                    'until its behavior is implemented and tested.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Divider(color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _BuildFact(
                        icon: Icons.hub_outlined,
                        label: 'Provider',
                        value: provider.id,
                      ),
                      _BuildFact(
                        icon: Icons.memory_outlined,
                        label: 'Rust core',
                        value: bootstrap.coreVersion,
                      ),
                    ],
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

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.providerName});

  final String providerName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '$providerName core connected',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildFact extends StatelessWidget {
  const _BuildFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
