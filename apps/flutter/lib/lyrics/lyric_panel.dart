import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';

Future<void> showLyrics(
  BuildContext context,
  LyricController controller,
  VoidCallback onSignInAgain, {
  Widget Function(Widget child)? modalContentWrapper,
  Listenable? playbackState,
  bool Function()? canSeek,
  Future<void> Function(int positionMs)? onSeek,
}) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _wrapModalContent(
          LyricPanel(
            controller: controller,
            onClose: () => Navigator.of(context).pop(),
            onSignInAgain: onSignInAgain,
            playbackState: playbackState,
            canSeek: canSeek,
            onSeek: onSeek,
          ),
          modalContentWrapper,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: _wrapModalContent(
          LyricPanel(
            controller: controller,
            onClose: () => Navigator.of(context).pop(),
            onSignInAgain: onSignInAgain,
            playbackState: playbackState,
            canSeek: canSeek,
            onSeek: onSeek,
          ),
          modalContentWrapper,
        ),
      ),
    ),
  );
}

Widget _wrapModalContent(
  Widget child,
  Widget Function(Widget child)? wrapper,
) => wrapper?.call(child) ?? child;

class LyricPanel extends StatelessWidget {
  const LyricPanel({
    required this.controller,
    required this.onClose,
    required this.onSignInAgain,
    this.playbackState,
    this.canSeek,
    this.onSeek,
    this.showCloseButton = true,
    super.key,
  });

  final LyricController controller;
  final VoidCallback onClose;
  final VoidCallback onSignInAgain;
  final Listenable? playbackState;
  final bool Function()? canSeek;
  final Future<void> Function(int positionMs)? onSeek;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final playbackState = this.playbackState;
    return AnimatedBuilder(
      animation: playbackState == null
          ? controller
          : Listenable.merge([controller, playbackState]),
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
                    if (showCloseButton)
                      IconButton(
                        tooltip: 'Close lyrics',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _body(canSeek?.call() ?? false)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(bool seekEnabled) => switch (controller.stage) {
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
      onSeek: seekEnabled ? onSeek : null,
    ),
    LyricStage.unavailable => const _LyricMessage(
      key: ValueKey('lyrics-unavailable'),
      icon: Icons.lyrics_outlined,
      title: 'No synchronized lyrics',
      detail: 'QQ Music did not provide lyrics for this track.',
      announce: true,
    ),
    LyricStage.error => _LyricMessage(
      key: const ValueKey('lyrics-error'),
      icon: Icons.cloud_off_rounded,
      title: _errorTitle(controller.failure),
      detail: _errorDetail(controller.failure),
      announce: true,
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
      announce: true,
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
      announce: true,
      action: TextButton(
        key: const ValueKey('lyrics-sign-in-again'),
        onPressed: onSignInAgain,
        child: const Text('Sign in again'),
      ),
    ),
  };
}

class _LyricContent extends StatefulWidget {
  const _LyricContent({required this.controller, this.onSeek, super.key});

  final LyricController controller;
  final Future<void> Function(int positionMs)? onSeek;

  @override
  State<_LyricContent> createState() => _LyricContentState();
}

class _LyricContentState extends State<_LyricContent> {
  final ScrollController _scrollController = ScrollController();
  SynchronizedLyrics? _lastLyrics;
  int? _lineKeyIndex;
  GlobalKey? _activeLineKey;
  int? _lastActiveLineIndex;
  int _followAttempt = 0;
  bool _following = true;

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.controller.lyrics!;
    final lines = lyrics.lines;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    if (!identical(lyrics, _lastLyrics)) {
      _lastLyrics = lyrics;
      _lineKeyIndex = null;
      _activeLineKey = null;
      _lastActiveLineIndex = null;
      _followAttempt += 1;
      _following = true;
    }
    if (activeLineIndex != _lastActiveLineIndex) {
      _lastActiveLineIndex = activeLineIndex;
      if (_following && activeLineIndex != null) {
        _scheduleFollow(activeLineIndex, lines.length);
      }
    }

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: _onUserScroll,
          child: ListView.builder(
            key: const ValueKey('lyrics-line-list'),
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16, 20, 16, _following ? 20 : 88),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = _LyricLine(
                key: ValueKey('lyrics-line-$index'),
                line: lines[index],
                lineIndex: index,
                active: index == activeLineIndex,
                positionMs: widget.controller.positionMs,
                onSeek: widget.onSeek == null
                    ? null
                    : () => unawaited(widget.onSeek!(lines[index].startMs)),
              );
              if (index != activeLineIndex) return line;
              return KeyedSubtree(key: _lineKey(index), child: line);
            },
          ),
        ),
        if (!_following)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: FilledButton.tonalIcon(
                key: const ValueKey('lyrics-resume-following'),
                onPressed: _resumeFollowing,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Follow current line'),
              ),
            ),
          ),
      ],
    );
  }

  GlobalKey _lineKey(int index) {
    if (_lineKeyIndex != index) {
      _lineKeyIndex = index;
      _activeLineKey = GlobalKey(debugLabel: 'line-$index');
    }
    return _activeLineKey!;
  }

  bool _onUserScroll(UserScrollNotification notification) {
    if (_following && notification.direction != ScrollDirection.idle) {
      _followAttempt += 1;
      setState(() => _following = false);
    }
    return false;
  }

  void _resumeFollowing() {
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    setState(() => _following = true);
    if (activeLineIndex != null) {
      _scheduleFollow(activeLineIndex, widget.controller.lyrics!.lines.length);
    }
  }

  void _scheduleFollow(int lineIndex, int lineCount) {
    final attempt = ++_followAttempt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following || attempt != _followAttempt) return;
      unawaited(_followLine(lineIndex, lineCount, attempt));
    });
  }

  Future<void> _followLine(int lineIndex, int lineCount, int attempt) async {
    var targetContext = _lineKey(lineIndex).currentContext;
    if (targetContext == null && _scrollController.hasClients) {
      final position = _scrollController.position;
      final fraction = lineCount <= 1 ? 0.0 : lineIndex / (lineCount - 1);
      final estimatedOffset = (position.maxScrollExtent * fraction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      await _scrollController.animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || !_following || attempt != _followAttempt) return;
      await WidgetsBinding.instance.endOfFrame;
      targetContext = _lineKey(lineIndex).currentContext;
    }
    if (targetContext == null ||
        !targetContext.mounted ||
        !mounted ||
        !_following ||
        attempt != _followAttempt) {
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.45,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _followAttempt += 1;
    _scrollController.dispose();
    super.dispose();
  }
}

class _LyricLine extends StatelessWidget {
  const _LyricLine({
    required this.line,
    required this.lineIndex,
    required this.active,
    required this.positionMs,
    this.onSeek,
    super.key,
  });

  final SynchronizedLyricLine line;
  final int lineIndex;
  final bool active;
  final int positionMs;
  final VoidCallback? onSeek;

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
      button: onSeek != null,
      onTap: onSeek,
      child: InkWell(
        onTap: onSeek,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(18),
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
                    for (
                      var index = 0;
                      index < line.segments.length;
                      index += 1
                    )
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
              if (active &&
                  line.segments.isNotEmpty &&
                  !segmentsComposeLine) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 0,
                  runSpacing: 4,
                  children: [
                    for (
                      var index = 0;
                      index < line.segments.length;
                      index += 1
                    )
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
    this.announce = false,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool announce;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
      ],
    );
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
              if (announce)
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: '$title. $detail',
                  excludeSemantics: true,
                  child: copy,
                )
              else
                copy,
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
