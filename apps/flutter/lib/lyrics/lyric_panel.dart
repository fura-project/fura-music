import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutterustmusic/fura_toast.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
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
    animationStyle: furaDialogAnimationStyle(context),
    builder: (context) => FuraDialogTransition(
      child: Dialog(
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
    ),
  );
}

Widget _wrapModalContent(
  Widget child,
  Widget Function(Widget child)? wrapper,
) => wrapper?.call(child) ?? child;

class LyricPanel extends StatefulWidget {
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
  State<LyricPanel> createState() => _LyricPanelState();
}

class _LyricPanelState extends State<LyricPanel> {
  late bool _seekEnabled;

  @override
  void initState() {
    super.initState();
    _seekEnabled = widget.canSeek?.call() ?? false;
    widget.playbackState?.addListener(_handlePlaybackStateChanged);
  }

  @override
  void didUpdateWidget(LyricPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackState != widget.playbackState) {
      oldWidget.playbackState?.removeListener(_handlePlaybackStateChanged);
      widget.playbackState?.addListener(_handlePlaybackStateChanged);
    }
    _seekEnabled = widget.canSeek?.call() ?? false;
  }

  @override
  void dispose() {
    widget.playbackState?.removeListener(_handlePlaybackStateChanged);
    super.dispose();
  }

  void _handlePlaybackStateChanged() {
    if (!mounted) return;
    final nextSeekEnabled = widget.canSeek?.call() ?? false;
    if (nextSeekEnabled == _seekEnabled) return;
    setState(() => _seekEnabled = nextSeekEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller.stageListenable,
      builder: (context, _) {
        final seekEnabled = widget.canSeek?.call() ?? false;
        _seekEnabled = seekEnabled;
        final theme = Theme.of(context);
        final track = widget.controller.track;
        return SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.immersive ? 28 : 24,
                  widget.immersive ? 20 : 8,
                  widget.immersive ? 20 : 8,
                  widget.immersive ? 16 : 12,
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
                    if (widget.showCloseButton)
                      IconButton(
                        tooltip: context.l10n.lyricsClose,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
              if (!widget.immersive) const Divider(height: 1),
              Expanded(child: _body(context, seekEnabled)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, bool seekEnabled) =>
      switch (widget.controller.stage) {
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
          controller: widget.controller,
          onSeek: seekEnabled ? widget.onSeek : null,
          immersive: widget.immersive,
          auxiliaryMode: widget.auxiliaryMode,
        ),
        LyricStage.unavailable => _LyricMessage(
          key: const ValueKey('lyrics-unavailable'),
          icon: Icons.lyrics_outlined,
          title: context.l10n.lyricsUnavailableTitle,
          detail: context.l10n.lyricsUnavailableDetail(
            builtInProviderDisplayName(
              widget.controller.track?.providerId ?? '',
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
            widget.controller.failure,
            builtInProviderDisplayName(
              widget.controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          detail: _errorDetail(
            context.l10n,
            widget.controller.failure,
            builtInProviderDisplayName(
              widget.controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          announce: true,
          action: widget.controller.canRetry
              ? FilledButton.tonal(
                  key: const ValueKey('lyrics-retry'),
                  onPressed: widget.controller.retry,
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
              widget.controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          announce: true,
          action: TextButton(
            key: const ValueKey('lyrics-sign-in-again'),
            onPressed: widget.onSignInAgain,
            child: Text(context.l10n.authSignInAgain),
          ),
        ),
        LyricStage.credentialRejected => _LyricMessage(
          key: const ValueKey('lyrics-credential-rejected'),
          icon: Icons.lock_reset_rounded,
          title: context.l10n.lyricsSessionRejectedTitle(
            builtInProviderDisplayName(
              widget.controller.track?.providerId ?? '',
              context.l10n,
            ),
          ),
          detail: context.l10n.lyricsSessionRejectedDetail,
          announce: true,
          action: TextButton(
            key: const ValueKey('lyrics-sign-in-again'),
            onPressed: widget.onSignInAgain,
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
  bool _stopFollowingScheduled = false;
  int? _pendingStopFollowingAttempt;

  @override
  void initState() {
    super.initState();
    widget.controller.lineListenable.addListener(_handleControllerChanged);
  }

  @override
  void reassemble() {
    super.reassemble();
    widget.controller.lineListenable.removeListener(_handleControllerChanged);
    widget.controller.lineListenable.addListener(_handleControllerChanged);
    final lyrics = widget.controller.lyrics;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    if (_following && lyrics != null && activeLineIndex != null) {
      _scheduleFollow(activeLineIndex, lyrics.lines.length, animate: true);
    }
  }

  @override
  void didUpdateWidget(_LyricContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.lineListenable.removeListener(
        _handleControllerChanged,
      );
      widget.controller.lineListenable.addListener(_handleControllerChanged);
    }
    if (oldWidget.auxiliaryMode == widget.auxiliaryMode || !_following) return;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    if (activeLineIndex != null) {
      _scheduleFollow(
        activeLineIndex,
        widget.controller.lyrics?.lines.length ?? 0,
        animate: true,
      );
    }
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final lyrics = widget.controller.lyrics;
    if (lyrics == null) return;
    final initialMount = _lastLyrics == null;
    final lyricsChanged = !identical(lyrics, _lastLyrics);
    if (lyricsChanged) {
      _lastLyrics = lyrics;
      _lineKeys.clear();
      _lastActiveLineIndex = null;
      _followAttempt += 1;
      _following = true;
    }
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    final animate = !initialMount;
    if (activeLineIndex != _lastActiveLineIndex) {
      _lastActiveLineIndex = activeLineIndex;
      if (_following && activeLineIndex != null) {
        _startOrScheduleFollow(
          activeLineIndex,
          lyrics.lines.length,
          animate: animate,
        );
      }
    } else if (lyricsChanged && _following && lyrics.lines.isNotEmpty) {
      final needsResetToTop =
          _scrollController.hasClients && _scrollController.offset > 0.5;
      if (needsResetToTop) {
        _startOrScheduleFollow(0, lyrics.lines.length, animate: animate);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.controller.lyrics!;
    final lines = lyrics.lines;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    final initialMount = _lastLyrics == null;
    final lyricsChanged = !identical(lyrics, _lastLyrics);
    if (lyricsChanged) {
      _lastLyrics = lyrics;
      _lineKeys.clear();
      _lastActiveLineIndex = null;
      _followAttempt += 1;
      _following = true;
    }
    final animate = !initialMount;
    if (activeLineIndex != _lastActiveLineIndex) {
      _lastActiveLineIndex = activeLineIndex;
      if (_following && activeLineIndex != null) {
        _scheduleFollow(activeLineIndex, lines.length, animate: animate);
      }
    } else if (lyricsChanged && _following && lines.isNotEmpty) {
      final needsResetToTop =
          _scrollController.hasClients && _scrollController.offset > 0.5;
      if (needsResetToTop) {
        _scheduleFollow(0, lines.length, animate: animate);
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
                    final active = index == activeLineIndex;
                    return KeyedSubtree(
                      key: _lineKey(index),
                      child: _LyricLine(
                        key: ValueKey('lyrics-line-$index'),
                        line: lines[index],
                        lineIndex: index,
                        active: active,
                        immersive: widget.immersive,
                        auxiliaryMode: widget.auxiliaryMode,
                        positionMsListenable:
                            active && lines[index].segmentsComposeLine
                            ? widget.controller.positionMsListenable
                            : null,
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
      final attempt = ++_followAttempt;
      _pendingStopFollowingAttempt = attempt;
      if (!_stopFollowingScheduled) {
        _stopFollowingScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _stopFollowingScheduled = false;
          if (!mounted ||
              _pendingStopFollowingAttempt != _followAttempt ||
              !_following) {
            return;
          }
          _pendingStopFollowingAttempt = null;
          setState(() => _following = false);
        });
      }
    }
    return false;
  }

  void _resumeFollowing() {
    _pendingStopFollowingAttempt = null;
    final activeLineIndex = widget.controller.activeSelection?.lineIndex;
    setState(() => _following = true);
    if (activeLineIndex != null) {
      _scheduleFollow(
        activeLineIndex,
        widget.controller.lyrics!.lines.length,
        animate: true,
      );
    }
  }

  void _startOrScheduleFollow(
    int lineIndex,
    int lineCount, {
    required bool animate,
  }) {
    final phase = WidgetsBinding.instance.schedulerPhase;
    final canStartImmediately =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;
    final targetContext = _lineKey(lineIndex).currentContext;
    if (canStartImmediately &&
        targetContext != null &&
        targetContext.mounted &&
        _scrollController.hasClients) {
      final attempt = ++_followAttempt;
      unawaited(_followLine(lineIndex, lineCount, attempt, animate: animate));
      return;
    }
    _scheduleFollow(lineIndex, lineCount, animate: animate);
  }

  void _scheduleFollow(int lineIndex, int lineCount, {required bool animate}) {
    final attempt = ++_followAttempt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following || attempt != _followAttempt) return;
      unawaited(_followLine(lineIndex, lineCount, attempt, animate: animate));
    });
  }

  double _estimateLineOffset({
    required int lineIndex,
    required int lineCount,
    required ScrollPosition position,
  }) {
    int? minMounted;
    int? maxMounted;
    RenderBox? minBox;
    RenderBox? maxBox;
    BuildContext? sampleContext;
    var measuredHeightSum = 0.0;
    var measuredCount = 0;
    for (final entry in _lineKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null || !ctx.mounted) continue;
      final renderObject = ctx.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          !renderObject.attached) {
        continue;
      }
      sampleContext ??= ctx;
      final idx = entry.key;
      measuredHeightSum += renderObject.size.height;
      measuredCount += 1;
      if (minMounted == null || idx < minMounted) {
        minMounted = idx;
        minBox = renderObject;
      }
      if (maxMounted == null || idx > maxMounted) {
        maxMounted = idx;
        maxBox = renderObject;
      }
    }
    if (minMounted != null && maxMounted != null && measuredCount > 0) {
      final scrollableObject = sampleContext == null
          ? null
          : Scrollable.maybeOf(sampleContext)?.context.findRenderObject();
      final viewport =
          scrollableObject is RenderBox &&
              scrollableObject.hasSize &&
              scrollableObject.attached
          ? scrollableObject
          : null;
      final avgHeight = (measuredHeightSum / measuredCount).clamp(48.0, 240.0);
      final targetAnchor = position.viewportDimension * 0.38;
      if (lineIndex > maxMounted) {
        final maxBottomInScroll = viewport != null && maxBox != null
            ? position.pixels +
                  maxBox
                      .localToGlobal(
                        Offset(0, maxBox.size.height),
                        ancestor: viewport,
                      )
                      .dy
            : position.pixels + position.viewportDimension;
        final estimatedLineTop =
            maxBottomInScroll + (lineIndex - maxMounted - 1) * avgHeight;
        return (estimatedLineTop - targetAnchor).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
      }
      if (lineIndex < minMounted) {
        final minTopInScroll = viewport != null && minBox != null
            ? position.pixels +
                  minBox.localToGlobal(Offset.zero, ancestor: viewport).dy
            : position.pixels;
        final estimatedLineTop =
            minTopInScroll - (minMounted - lineIndex) * avgHeight;
        return (estimatedLineTop - targetAnchor).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
      }
    }
    final fraction = lineCount <= 1 ? 0.0 : lineIndex / (lineCount - 1);
    return (position.maxScrollExtent * fraction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  Future<void> _followLine(
    int lineIndex,
    int lineCount,
    int attempt, {
    required bool animate,
  }) async {
    var targetContext = _lineKey(lineIndex).currentContext;
    for (
      var step = 0;
      step < 4 && targetContext == null && _scrollController.hasClients;
      step += 1
    ) {
      final position = _scrollController.position;
      final estimatedOffset = _estimateLineOffset(
        lineIndex: lineIndex,
        lineCount: lineCount,
        position: position,
      );
      if ((estimatedOffset - position.pixels).abs() < 1.0) {
        break;
      }
      if (animate) {
        await _scrollController.animateTo(
          estimatedOffset,
          duration: Duration(milliseconds: step == 0 ? 180 : 90),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(estimatedOffset);
      }
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
      alignment: 0.38,
      duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _followAttempt += 1;
    widget.controller.lineListenable.removeListener(_handleControllerChanged);
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
    required this.positionMsListenable,
    this.onSeek,
    super.key,
  });

  final SynchronizedLyricLine line;
  final int lineIndex;
  final bool active;
  final bool immersive;
  final LyricAuxiliaryMode auxiliaryMode;
  final ValueListenable<int>? positionMsListenable;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        (immersive
            ? theme.textTheme.titleLarge
            : theme.textTheme.titleMedium) ??
        const TextStyle(fontSize: 18);
    final textStyle = baseStyle.copyWith(
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      color: active
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    final segmentsComposeLine = line.segmentsComposeLine;
    final (auxiliaryText, auxiliaryIsRomanization) = switch (auxiliaryMode) {
      LyricAuxiliaryMode.auto =>
        line.translation != null
            ? (line.translation, false)
            : (line.romanization, true),
      LyricAuxiliaryMode.translation => (line.translation, false),
      LyricAuxiliaryMode.romanization => (line.romanization, true),
      LyricAuxiliaryMode.off => (null, false),
    };

    Widget buildSegments(int positionMs) => Wrap(
      spacing: 0,
      runSpacing: 4,
      children: [
        for (var index = 0; index < line.segments.length; index += 1)
          _TimedSegment(
            key: ValueKey('lyrics-word-$lineIndex-$index'),
            segment: line.segments[index],
            positionMs: positionMs,
          ),
      ],
    );

    final Widget primaryText;
    if (segmentsComposeLine) {
      final listenable = positionMsListenable;
      if (active && listenable != null) {
        primaryText = ValueListenableBuilder<int>(
          valueListenable: listenable,
          builder: (context, positionMs, _) => buildSegments(positionMs),
        );
      } else {
        primaryText = buildSegments(-1);
      }
    } else {
      primaryText = Text(line.text);
    }

    return Semantics(
      selected: active,
      button: onSeek != null,
      onTap: onSeek,
      child: InkWell(
        onTap: onSeek,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(immersive ? 22 : 18),
        child: Container(
          margin: EdgeInsets.symmetric(vertical: immersive ? 6 : 4),
          padding: EdgeInsets.symmetric(
            horizontal: immersive ? 18 : 16,
            vertical: immersive ? 16 : 14,
          ),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.56)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(immersive ? 22 : 18),
          ),
          child: DefaultTextStyle.merge(
            style: textStyle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                primaryText,
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
      ),
    );
  }
}

class _TimedSegment extends StatelessWidget {
  const _TimedSegment({
    required this.segment,
    required this.positionMs,
    super.key,
  });

  final TimedLyricSegment segment;
  final int positionMs;

  @override
  Widget build(BuildContext context) {
    final progress = _progress(segment, positionMs);
    final colors = Theme.of(context).colorScheme;
    final animatedStyle = DefaultTextStyle.of(context).style;
    final activeLine = positionMs >= 0;
    final unsungColor = activeLine
        ? Color.lerp(colors.onSurfaceVariant, colors.onSurface, 0.35)!
        : colors.onSurfaceVariant;
    final unsungText = Text(
      segment.text,
      style: animatedStyle.copyWith(color: unsungColor),
    );
    final painted = progress <= 0
        ? unsungText
        : progress >= 1
        ? Text(
            segment.text,
            style: animatedStyle.copyWith(color: colors.primary),
          )
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                colors.primary,
                colors.primary,
                unsungColor,
                unsungColor,
              ],
              stops: [0, progress, progress, 1],
            ).createShader(bounds),
            child: Text(
              segment.text,
              style: animatedStyle.copyWith(color: Colors.white),
            ),
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
  Widget build(BuildContext context) =>
      MusicLoadingPanel(label: context.l10n.lyricsLoading);
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
  Widget build(BuildContext context) => MusicContentStatePanel(
    icon: icon,
    title: title,
    detail: detail,
    liveRegion: announce,
    announcementLabel: announce
        ? context.l10n.lyricsAnnouncement(detail, title)
        : null,
    action: action,
  );
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
