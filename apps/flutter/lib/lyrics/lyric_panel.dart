import 'package:flutter/material.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';

Future<void> showLyrics(
  BuildContext context,
  LyricController controller,
  VoidCallback onSignInAgain,
) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        child: LyricPanel(
          controller: controller,
          onClose: () => Navigator.of(context).pop(),
          onSignInAgain: onSignInAgain,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: LyricPanel(
          controller: controller,
          onClose: () => Navigator.of(context).pop(),
          onSignInAgain: onSignInAgain,
        ),
      ),
    ),
  );
}

class LyricPanel extends StatelessWidget {
  const LyricPanel({
    required this.controller,
    required this.onClose,
    required this.onSignInAgain,
    super.key,
  });

  final LyricController controller;
  final VoidCallback onClose;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final track = controller.track;
        return SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lyrics',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (track != null)
                            Text(
                              track.title,
                              key: const ValueKey('lyrics-track-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close lyrics',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _body()),
            ],
          ),
        );
      },
    );
  }

  Widget _body() => switch (controller.stage) {
    LyricStage.idle => const _LyricMessage(
      key: ValueKey('lyrics-idle'),
      icon: Icons.lyrics_outlined,
      title: 'Start a track to see its lyrics',
      detail: 'Synchronized lyrics will follow the current queue track.',
    ),
    LyricStage.loading => const _LyricLoading(key: ValueKey('lyrics-loading')),
    LyricStage.content => _LyricContent(
      key: const ValueKey('lyrics-content'),
      controller: controller,
    ),
    LyricStage.unavailable => const _LyricMessage(
      key: ValueKey('lyrics-unavailable'),
      icon: Icons.lyrics_outlined,
      title: 'No synchronized lyrics',
      detail: 'QQ Music did not provide lyrics for this track.',
    ),
    LyricStage.error => _LyricMessage(
      key: const ValueKey('lyrics-error'),
      icon: Icons.cloud_off_rounded,
      title: _errorTitle(controller.failure),
      detail: _errorDetail(controller.failure),
      action: controller.canRetry
          ? FilledButton.tonal(
              key: const ValueKey('lyrics-retry'),
              onPressed: controller.retry,
              child: const Text('Try again'),
            )
          : null,
    ),
    LyricStage.authenticationRequired => _LyricMessage(
      key: const ValueKey('lyrics-authentication-required'),
      icon: Icons.lock_outline_rounded,
      title: 'Sign in to load lyrics',
      detail: 'Your current session cannot request QQ Music lyrics.',
      action: TextButton(
        key: const ValueKey('lyrics-sign-in-again'),
        onPressed: onSignInAgain,
        child: const Text('Sign in again'),
      ),
    ),
    LyricStage.credentialRejected => _LyricMessage(
      key: const ValueKey('lyrics-credential-rejected'),
      icon: Icons.lock_reset_rounded,
      title: 'QQ Music session rejected',
      detail: 'Sign in again before requesting lyrics.',
      action: TextButton(
        key: const ValueKey('lyrics-sign-in-again'),
        onPressed: onSignInAgain,
        child: const Text('Sign in again'),
      ),
    ),
  };
}

class _LyricContent extends StatelessWidget {
  const _LyricContent({required this.controller, super.key});

  final LyricController controller;

  @override
  Widget build(BuildContext context) {
    final lines = controller.lyrics!.lines;
    final activeLineIndex = controller.activeSelection?.lineIndex;
    return ListView.builder(
      key: const ValueKey('lyrics-line-list'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: lines.length,
      itemBuilder: (context, index) => _LyricLine(
        key: ValueKey('lyrics-line-$index'),
        line: lines[index],
        lineIndex: index,
        active: index == activeLineIndex,
        positionMs: controller.positionMs,
      ),
    );
  }
}

class _LyricLine extends StatelessWidget {
  const _LyricLine({
    required this.line,
    required this.lineIndex,
    required this.active,
    required this.positionMs,
    super.key,
  });

  final SynchronizedLyricLine line;
  final int lineIndex;
  final bool active;
  final int positionMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      color: active
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    final segmentsComposeLine =
        line.segments.isNotEmpty &&
        line.segments.map((segment) => segment.text).join() == line.text;

    return Semantics(
      selected: active,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.52)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (active && segmentsComposeLine)
              Wrap(
                spacing: 0,
                runSpacing: 4,
                children: [
                  for (var index = 0; index < line.segments.length; index += 1)
                    _TimedSegment(
                      key: ValueKey('lyrics-word-$lineIndex-$index'),
                      segment: line.segments[index],
                      positionMs: positionMs,
                      style: textStyle,
                    ),
                ],
              )
            else
              Text(line.text, style: textStyle),
            if (active && line.segments.isNotEmpty && !segmentsComposeLine) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 0,
                runSpacing: 4,
                children: [
                  for (var index = 0; index < line.segments.length; index += 1)
                    _TimedSegment(
                      key: ValueKey('lyrics-word-$lineIndex-$index'),
                      segment: line.segments[index],
                      positionMs: positionMs,
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ],
            if (line.translation case final translation?) ...[
              const SizedBox(height: 6),
              Text(
                translation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (line.romanization case final romanization?) ...[
              const SizedBox(height: 4),
              Text(
                romanization,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimedSegment extends StatelessWidget {
  const _TimedSegment({
    required this.segment,
    required this.positionMs,
    required this.style,
    super.key,
  });

  final TimedLyricSegment segment;
  final int positionMs;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final progress = _progress(segment, positionMs);
    final colors = Theme.of(context).colorScheme;
    final text = Text(segment.text, style: style);
    final painted = progress <= 0
        ? text
        : progress >= 1
        ? Text(segment.text, style: style?.copyWith(color: colors.primary))
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                colors.primary,
                colors.primary,
                colors.onSurfaceVariant,
                colors.onSurfaceVariant,
              ],
              stops: [0, progress, progress, 1],
            ).createShader(bounds),
            child: text,
          );
    return Semantics(
      label: segment.text,
      value: '${(progress * 100).round()}% complete',
      excludeSemantics: true,
      child: painted,
    );
  }
}

class _LyricLoading extends StatelessWidget {
  const _LyricLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 18),
        Text(
          'Loading synchronized lyrics…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _LyricMessage extends StatelessWidget {
  const _LyricMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (action case final action?) ...[
                const SizedBox(height: 20),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

double _progress(TimedLyricSegment segment, int positionMs) {
  if (segment.durationMs <= 0 || positionMs <= segment.startMs) return 0;
  if (positionMs >= segment.endMs) return 1;
  return (positionMs - segment.startMs) / segment.durationMs;
}

String _errorTitle(LyricFailure? failure) => switch (failure) {
  LyricFailure.network => 'Couldn’t reach QQ Music',
  LyricFailure.serviceUnavailable => 'Lyrics are unavailable right now',
  LyricFailure.alreadyRunning => 'Another lyric request is still running',
  _ => 'Couldn’t load synchronized lyrics',
};

String _errorDetail(LyricFailure? failure) => switch (failure) {
  LyricFailure.network =>
    'Your session is unchanged. Check your connection and try again.',
  LyricFailure.serviceUnavailable =>
    'Your session is unchanged. Try requesting this track again later.',
  LyricFailure.alreadyRunning =>
    'Wait for the current request to finish before trying again.',
  LyricFailure.cancelled || LyricFailure.replaced =>
    'The lyric request was replaced before it completed.',
  _ => 'QQ Music returned lyrics this build could not safely present.',
};
