import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';

class OwnedLibraryPage extends StatefulWidget {
  const OwnedLibraryPage({
    required this.gateway,
    required this.onSignInAgain,
    super.key,
  });

  final OwnedLibraryGateway gateway;
  final VoidCallback onSignInAgain;

  @override
  State<OwnedLibraryPage> createState() => _OwnedLibraryPageState();
}

class _OwnedLibraryPageState extends State<OwnedLibraryPage> {
  late final OwnedLibraryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OwnedLibraryController(widget.gateway);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your music'),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => IconButton(
              tooltip: 'Refresh created playlists',
              onPressed: _controller.stage == OwnedLibraryStage.loading
                  ? null
                  : _controller.load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) => switch (_controller.stage) {
    OwnedLibraryStage.loading => const _LibraryLoading(
      key: ValueKey('owned-library-loading'),
    ),
    OwnedLibraryStage.content => _PlaylistCollection(
      key: const ValueKey('owned-library-content'),
      playlists: _controller.playlists,
    ),
    OwnedLibraryStage.empty => const _LibraryEmpty(
      key: ValueKey('owned-library-empty'),
    ),
    OwnedLibraryStage.error => _LibraryFailure(
      key: const ValueKey('owned-library-error'),
      failure: _controller.failure,
      canRetry: _controller.canRetry,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
    OwnedLibraryStage.authenticationRequired ||
    OwnedLibraryStage.credentialRejected => _LibraryFailure(
      key: const ValueKey('owned-library-authentication-error'),
      failure: _controller.failure,
      canRetry: false,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
  };
}

class _PlaylistCollection extends StatelessWidget {
  const _PlaylistCollection({required this.playlists, super.key});

  final List<OwnedPlaylistSummary> playlists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 48 : 20,
            desktop ? 28 : 16,
            desktop ? 48 : 20,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playlists you created',
                style:
                    (desktop
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${playlists.length} from QQ Music',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: desktop ? 28 : 20),
              Expanded(
                child: desktop
                    ? GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisExtent: 270,
                              crossAxisSpacing: 24,
                              mainAxisSpacing: 28,
                            ),
                        itemCount: playlists.length,
                        itemBuilder: (context, index) =>
                            _PlaylistGridItem(playlist: playlists[index]),
                      )
                    : ListView.separated(
                        itemCount: playlists.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _PlaylistListItem(playlist: playlists[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistGridItem extends StatelessWidget {
  const _PlaylistGridItem({required this.playlist});

  final OwnedPlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _semanticLabel(playlist),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _PlaylistArtwork(playlist: playlist)),
          const SizedBox(height: 12),
          Text(
            playlist.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (playlist.trackCount case final count?) ...[
            const SizedBox(height: 4),
            Text(
              '$count tracks',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistListItem extends StatelessWidget {
  const _PlaylistListItem({required this.playlist});

  final OwnedPlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _semanticLabel(playlist),
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 72,
              child: _PlaylistArtwork(playlist: playlist),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (playlist.trackCount case final count?) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$count tracks',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.playlist});

  final OwnedPlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final uri = playlist.artworkUri;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: uri == null
          ? const _ArtworkPlaceholder()
          : Image.network(
              uri,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => const _ArtworkPlaceholder(),
            ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: colors.onPrimaryContainer,
          size: 38,
        ),
      ),
    );
  }
}

class _LibraryLoading extends StatelessWidget {
  const _LibraryLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 44,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        Text(
          'Loading your playlists…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({super.key});

  @override
  Widget build(BuildContext context) => _CenteredLibraryMessage(
    icon: Icons.library_music_outlined,
    title: 'No created playlists yet',
    detail: 'Playlists you create in QQ Music will appear here.',
    actions: const [],
  );
}

class _LibraryFailure extends StatelessWidget {
  const _LibraryFailure({
    required this.failure,
    required this.canRetry,
    required this.onRetry,
    required this.onSignInAgain,
    super.key,
  });

  final OwnedLibraryFailure? failure;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = _failureCopy(failure);
    return _CenteredLibraryMessage(
      icon:
          failure == OwnedLibraryFailure.credentialRejected ||
              failure ==
                  OwnedLibraryFailure.credentialRejectedStorageCleanupFailed
          ? Icons.lock_reset_rounded
          : Icons.cloud_off_rounded,
      title: title,
      detail: detail,
      actions: [
        if (canRetry)
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        TextButton(
          onPressed: onSignInAgain,
          child: const Text('Sign in again'),
        ),
      ],
    );
  }
}

class _CenteredLibraryMessage extends StatelessWidget {
  const _CenteredLibraryMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

(String, String) _failureCopy(
  OwnedLibraryFailure? failure,
) => switch (failure) {
  OwnedLibraryFailure.network => (
    'Couldn’t reach QQ Music',
    'Your session is still active. Check your connection and try again.',
  ),
  OwnedLibraryFailure.serviceUnavailable => (
    'QQ Music is unavailable',
    'Your session was kept unchanged. Try loading your playlists again later.',
  ),
  OwnedLibraryFailure.invalidResponse => (
    'QQ Music changed its response',
    'This client stopped safely instead of showing an incomplete library.',
  ),
  OwnedLibraryFailure.credentialRejected => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, so the stored session was removed.',
  ),
  OwnedLibraryFailure.credentialRejectedStorageCleanupFailed => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, but secure storage could not remove it.',
  ),
  OwnedLibraryFailure.authenticationRequired ||
  OwnedLibraryFailure.replaced ||
  OwnedLibraryFailure.cancelled => (
    'Sign in to load your playlists',
    'The account state changed before this library request finished.',
  ),
  OwnedLibraryFailure.coreUnavailable => (
    'The music core is unavailable',
    'Your library could not be loaded safely. Try again after restarting.',
  ),
  OwnedLibraryFailure.alreadyRunning => (
    'A library request is already running',
    'Wait for it to finish, then try again.',
  ),
  null => (
    'Couldn’t load your playlists',
    'Try again or sign in with a fresh QQ Music session.',
  ),
};

String _semanticLabel(OwnedPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null ? playlist.title : '${playlist.title}, $count tracks';
}
