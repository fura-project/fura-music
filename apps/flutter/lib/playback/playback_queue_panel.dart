import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';

Future<void> showPlaybackQueue(
  BuildContext context,
  QueuePlaybackController controller,
) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: PlaybackShortcuts(
          controller: controller,
          child: PlaybackQueuePanel(
            controller: controller,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: PlaybackShortcuts(
          controller: controller,
          child: PlaybackQueuePanel(
            controller: controller,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

class PlaybackQueuePanel extends StatelessWidget {
  const PlaybackQueuePanel({
    required this.controller,
    required this.onClose,
    super.key,
  });

  final QueuePlaybackController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tracks = controller.tracks;
        final theme = Theme.of(context);
        return SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Queue',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tracks.isNotEmpty)
                      TextButton(
                        key: const ValueKey('queue-clear'),
                        onPressed: () => unawaited(controller.clear()),
                        child: const Text('Clear'),
                      ),
                    IconButton(
                      tooltip: 'Close queue',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (controller.failure case final failure?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _failureCopy(failure),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'The queue is empty. Choose a track from a playlist.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final current = index == controller.currentIndex;
                          final artist = track.artistNames.isEmpty
                              ? 'Unknown artist'
                              : track.artistNames.join(' · ');
                          return Semantics(
                            selected: current,
                            button: true,
                            child: ListTile(
                              key: ValueKey('queue-entry-$index'),
                              selected: current,
                              selectedTileColor:
                                  theme.colorScheme.secondaryContainer,
                              leading: SizedBox.square(
                                dimension: 32,
                                child: Center(
                                  child: current
                                      ? Icon(
                                          Icons.graphic_eq_rounded,
                                          color: theme.colorScheme.primary,
                                        )
                                      : Text('${index + 1}'),
                                ),
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: current
                                  ? null
                                  : () => unawaited(controller.select(index)),
                              trailing: IconButton(
                                key: ValueKey('queue-remove-$index'),
                                tooltip: 'Remove from queue',
                                onPressed: () =>
                                    unawaited(controller.remove(index)),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _failureCopy(PlaybackQueueFailure failure) => switch (failure) {
  PlaybackQueueFailure.invalidTrack =>
    'A queue entry could not be represented safely.',
  PlaybackQueueFailure.invalidPosition =>
    'That queue position is no longer available.',
  PlaybackQueueFailure.coreUnavailable =>
    'The music core could not update the queue.',
  PlaybackQueueFailure.invalidResponse =>
    'The music core returned an invalid queue state.',
};
