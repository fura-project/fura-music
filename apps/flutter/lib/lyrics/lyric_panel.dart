import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';
import 'package:flutterustmusic/provider_presentation.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

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
    this.immersive = false,
    this.auxiliaryMode = LyricAuxiliaryMode.auto,
    super.key,
  });

  final LyricController controller;
  final VoidCallback onClose;
  final VoidCallback onSignInAgain;
  final Listenable? playbackState;
  final bool Function()? canSeek;
  final Future<void> Function(int positionMs)? onSeek;
  final bool showCloseButton;
  final bool immersive;
  final LyricAuxiliaryMode auxiliaryMode;

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
                padding: EdgeInsets.fromLTRB(
                  immersive ? 28 : 24,
                  immersive ? 20 : 8,
                  immersive ? 20 : 8,
                  immersive ? 16 : 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.lyricsTitle,
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
                        tooltip: context.l10n.lyricsClose,
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
              if (!immersive) const Divider(height: 1),
              Expanded(child: _body(context, canSeek?.call() ?? false)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, bool seekEnabled) =>
      switch (controller.stage) {
        LyricStage.idle => _LyricMessage(
          key: const ValueKey('lyrics-idle'),
          icon: Icons.lyrics_outlined,
          title: context.l10n.lyricsIdleTitle,
          detail: context.l10n.lyricsIdleDetail,
        ),
        LyricStage.loading => const _LyricLoading(
          key: ValueKey('lyrics-loading'),
        ),
        LyricStage.content => _LyricContent(
          key: const ValueKey('lyrics-content'),
          controller: controller,
          onSeek: seekEnabled ? onSeek : null,
          immersive: immersive,
          auxiliaryMode: auxiliaryMode,
        ),
        LyricStage.unavailable => _LyricMessage(
          key: const ValueKey('lyrics-unavailable'),
          icon: Icons.lyrics_outlined,
          title: context.l10n.lyricsUnavailableTitle,
          detail: context.l10n.lyricsUnavailableDetail(
            builtInProviderDisplayName(
              controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          announce: true,
        ),
        LyricStage.error => _LyricMessage(
          key: const ValueKey('lyrics-error'),
          icon: Icons.cloud_off_rounded,
          title: _errorTitle(
            context.l10n,
            controller.failure,
            builtInProviderDisplayName(
              controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          detail: _errorDetail(
            context.l10n,
            controller.failure,
            builtInProviderDisplayName(
              controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          announce: true,
          action: controller.canRetry
              ? FilledButton.tonal(
                  key: const ValueKey('lyrics-retry'),
                  onPressed: controller.retry,
                  child: Text(context.l10n.commonRetry),
                )
              : null,
        ),
        LyricStage.authenticationRequired => _LyricMessage(
          key: const ValueKey('lyrics-authentication-required'),
          icon: Icons.lock_outline_rounded,
          title: context.l10n.lyricsSignInTitle,
          detail: context.l10n.lyricsSignInDetail(
            builtInProviderDisplayName(
              controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          announce: true,
          action: TextButton(
            key: const ValueKey('lyrics-sign-in-again'),
            onPressed: onSignInAgain,
            child: Text(context.l10n.authSignInAgain),
          ),
        ),
        LyricStage.credentialRejected => _LyricMessage(
          key: const ValueKey('lyrics-credential-rejected'),
          icon: Icons.lock_reset_rounded,
          title: context.l10n.lyricsSessionRejectedTitle(
            builtInProviderDisplayName(
              controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          detail: context.l10n.lyricsSessionRejectedDetail,
          announce: true,
          action: TextButton(
            key: const ValueKey('lyrics-sign-in-again'),
            onPressed: onSignInAgain,
            child: Text(context.l10n.authSignInAgain),
          ),
        ),
      };
}

class _LyricContent extends StatefulWidget {
  const _LyricContent({
    required this.controller,
    required this.immersive,
    required this.auxiliaryMode,
    this.onSeek,
    super.key,
  });

  final LyricController controller;
  final bool immersive;
  final LyricAuxiliaryMode auxiliaryMode;
  final Future<void> Function(int positionMs)? onSeek;

  @override
  State<_LyricContent> createState() => _LyricContentState();
}

class _LyricContentState extends State<_LyricContent> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  SynchronizedLyrics? _lastLyrics;
  int? _lastActiveLineIndex;
  int _followAttempt = 0;
  bool _following = true;

  @override
  void didUpdateWidget(_LyricContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auxiliaryMode == widget.auxiliaryMode || !_following) return;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    if (activeLineIndex != null) {
      _scheduleFollow(
        activeLineIndex,
        widget.controller.lyrics?.lines.length ?? 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.controller.lyrics!;
    final lines = lyrics.lines;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    if (!identical(lyrics, _lastLyrics)) {
      _lastLyrics = lyrics;
      _lineKeys.clear();
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

    return Column(
      children: [
        if (lyrics.omittedLineCount > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.immersive ? 20 : 16,
              0,
              widget.immersive ? 20 : 16,
              8,
            ),
            child: PartialResultsNotice(
              omittedCount: lyrics.omittedLineCount,
              resultRevision: widget.controller.partialResultRevision,
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<UserScrollNotification>(
                onNotification: _onUserScroll,
                child: ListView.builder(
                  key: const ValueKey('lyrics-line-list'),
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    widget.immersive ? 20 : 16,
                    widget.immersive ? 12 : 20,
                    widget.immersive ? 20 : 16,
                    _following ? 20 : 88,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    return KeyedSubtree(
                      key: _lineKey(index),
                      child: _LyricLine(
                        key: ValueKey('lyrics-line-$index'),
                        line: lines[index],
                        lineIndex: index,
                        active: index == activeLineIndex,
                        immersive: widget.immersive,
                        auxiliaryMode: widget.auxiliaryMode,
                        positionMs: widget.controller.positionMs,
                        onSeek: widget.onSeek == null
                            ? null
                            : () => unawaited(
                                widget.onSeek!(lines[index].startMs),
                              ),
                      ),
                    );
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
                      label: Text(context.l10n.lyricsFollowCurrent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  GlobalKey _lineKey(int index) => _lineKeys.putIfAbsent(
    index,
    () => GlobalKey(debugLabel: 'lyrics-line-$index'),
  );

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
    required this.immersive,
    required this.auxiliaryMode,
    required this.positionMs,
    this.onSeek,
    super.key,
  });

  final SynchronizedLyricLine line;
  final int lineIndex;
  final bool active;
  final bool immersive;
  final LyricAuxiliaryMode auxiliaryMode;
  final int positionMs;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        (immersive
                ? active
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleLarge
                : theme.textTheme.titleMedium)
            ?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            );
    final segmentsComposeLine =
        line.segments.isNotEmpty &&
        line.segments.map((segment) => segment.text).join() == line.text;
    final (auxiliaryText, auxiliaryIsRomanization) = switch (auxiliaryMode) {
      LyricAuxiliaryMode.auto =>
        line.translation != null
            ? (line.translation, false)
            : (line.romanization, true),
      LyricAuxiliaryMode.translation => (line.translation, false),
      LyricAuxiliaryMode.romanization => (line.romanization, true),
      LyricAuxiliaryMode.off => (null, false),
    };

    return Semantics(
      selected: active,
      button: onSeek != null,
      onTap: onSeek,
      child: InkWell(
        onTap: onSeek,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(immersive ? 22 : 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(vertical: immersive ? 6 : 4),
          padding: EdgeInsets.symmetric(
            horizontal: immersive ? 18 : 16,
            vertical: immersive ? 16 : 14,
          ),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.52)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(immersive ? 22 : 18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (segmentsComposeLine)
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
                        positionMs: active ? positionMs : -1,
                        style: textStyle,
                      ),
                  ],
                )
              else
                Text(line.text, style: textStyle),
              if (auxiliaryText case final auxiliary?) ...[
                const SizedBox(height: 6),
                Text(
                  auxiliary,
                  key: ValueKey(
                    auxiliaryIsRomanization
                        ? 'lyrics-romanization-$lineIndex'
                        : 'lyrics-translation-$lineIndex',
                  ),
                  softWrap: true,
                  maxLines: null,
                  overflow: TextOverflow.visible,
                  textWidthBasis: TextWidthBasis.parent,
                  style: auxiliaryIsRomanization
                      ? theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : (immersive
                                ? theme.textTheme.bodyLarge
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
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
      value: context.l10n.lyricsSegmentProgress((progress * 100).round()),
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
          context.l10n.lyricsLoading,
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
                  label: context.l10n.lyricsAnnouncement(detail, title),
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

String _errorTitle(
  AppLocalizations l10n,
  LyricFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  LyricFailure.network => l10n.lyricsFailureNetworkTitle(providerDisplayName),
  LyricFailure.serviceUnavailable => l10n.lyricsFailureServiceTitle,
  LyricFailure.alreadyRunning => l10n.lyricsFailureRunningTitle,
  _ => l10n.lyricsFailureGenericTitle,
};

String _errorDetail(
  AppLocalizations l10n,
  LyricFailure? failure,
  String providerDisplayName,
) => switch (failure) {
  LyricFailure.network => l10n.lyricsFailureNetworkDetail,
  LyricFailure.serviceUnavailable => l10n.lyricsFailureServiceDetail,
  LyricFailure.alreadyRunning => l10n.lyricsFailureRunningDetail,
  LyricFailure.cancelled ||
  LyricFailure.replaced => l10n.lyricsFailureReplacedDetail,
  _ => l10n.lyricsFailureInvalidDetail(providerDisplayName),
};
