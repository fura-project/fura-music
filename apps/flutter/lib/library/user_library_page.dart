import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterustmusic/adaptive_confirmation.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_page.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_shortcuts.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

class UserLibraryPage extends StatefulWidget {
  const UserLibraryPage({
    required this.gateway,
    required this.detailGateway,
    required this.mediaResolutionGateway,
    required this.lyricGateway,
    required this.playbackQueueGateway,
    required this.audioEngine,
    required this.onSignInAgain,
    required this.onSignOut,
    super.key,
  });

  final UserLibraryGateway gateway;
  final PlaylistDetailGateway detailGateway;
  final MediaResolutionGateway mediaResolutionGateway;
  final LyricGateway lyricGateway;
  final PlaybackQueueGateway playbackQueueGateway;
  final ForegroundAudioEngine audioEngine;
  final VoidCallback onSignInAgain;
  final Future<CredentialSignOutResult> Function() onSignOut;

  @override
  State<UserLibraryPage> createState() => _UserLibraryPageState();
}

class _UserLibraryPageState extends State<UserLibraryPage> {
  late final UserLibraryController _controller;
  late final QueuePlaybackController _queuePlaybackController;
  UserPlaylistSummary? _selectedPlaylist;
  bool _handledLyricCredentialRejection = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _controller = UserLibraryController(widget.gateway);
    _queuePlaybackController = QueuePlaybackController(
      widget.playbackQueueGateway,
      TrackPlaybackController(
        widget.mediaResolutionGateway,
        ForegroundPlaybackController(widget.audioEngine),
      ),
      lyrics: LyricController(widget.lyricGateway),
    );
    _queuePlaybackController.addListener(_onQueuePlaybackChanged);
    unawaited(_controller.load());
  }

  void _onQueuePlaybackChanged() {
    if (!mounted) return;
    if (_queuePlaybackController.lyrics?.stage !=
        LyricStage.credentialRejected) {
      _handledLyricCredentialRejection = false;
      return;
    }
    if (_handledLyricCredentialRejection) return;
    _handledLyricCredentialRejection = true;
    widget.onSignInAgain();
  }

  @override
  void dispose() {
    _controller.dispose();
    _queuePlaybackController.removeListener(_onQueuePlaybackChanged);
    _queuePlaybackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlaylist = _selectedPlaylist;
    final page = selectedPlaylist != null
        ? PlaylistDetailPage(
            key: ValueKey('playlist-detail-${selectedPlaylist.opaqueId}'),
            playlist: selectedPlaylist,
            gateway: widget.detailGateway,
            queuePlaybackController: _queuePlaybackController,
            onBack: () => setState(() => _selectedPlaylist = null),
            onSignInAgain: widget.onSignInAgain,
          )
        : _libraryScaffold();
    return PlaybackShortcuts(controller: _queuePlaybackController, child: page);
  }

  Widget _libraryScaffold() => Scaffold(
    appBar: AppBar(
      title: const Text('Your music'),
      actions: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => IconButton(
            tooltip: 'Refresh playlists',
            onPressed: _controller.stage == UserLibraryStage.loading
                ? null
                : _controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        IconButton(
          key: const ValueKey('sign-out'),
          tooltip: 'Sign out',
          onPressed: _signingOut ? null : _confirmSignOut,
          icon: const Icon(Icons.logout_rounded),
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
    bottomNavigationBar: NowPlayingBar(
      controller: _queuePlaybackController,
      onSignInAgain: widget.onSignInAgain,
    ),
  );

  Future<void> _confirmSignOut() async {
    final confirmed = await showAdaptiveConfirmation(
      context,
      title: 'Sign out on this device?',
      message:
          'This will stop playback and remove the saved QQ Music session '
          'from this device.',
      confirmLabel: 'Sign out',
      cancelKey: const ValueKey('sign-out-cancel'),
      confirmKey: const ValueKey('sign-out-confirm'),
      sheetKey: const ValueKey('sign-out-confirmation-sheet'),
      dialogKey: const ValueKey('sign-out-confirmation-dialog'),
      wrapper: (child) =>
          PlaybackShortcuts(controller: _queuePlaybackController, child: child),
    );
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    final signOut = widget.onSignOut();
    await _queuePlaybackController.playback.stop();
    final result = await signOut;
    if (!mounted) return;
    setState(() => _signingOut = false);
    if (result == CredentialSignOutResult.coreUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t sign out. Your local session is unchanged.'),
        ),
      );
    }
  }

  Widget _body(BuildContext context) => switch (_controller.stage) {
    UserLibraryStage.loading => const _LibraryLoading(
      key: ValueKey('user-library-loading'),
    ),
    UserLibraryStage.content => _PlaylistCollection(
      key: const ValueKey('user-library-content'),
      playlists: _controller.playlists,
      onSelected: (playlist) => setState(() => _selectedPlaylist = playlist),
    ),
    UserLibraryStage.empty => const _LibraryEmpty(
      key: ValueKey('user-library-empty'),
    ),
    UserLibraryStage.error => _LibraryFailure(
      key: const ValueKey('user-library-error'),
      failure: _controller.failure,
      canRetry: _controller.canRetry,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
    UserLibraryStage.authenticationRequired ||
    UserLibraryStage.credentialRejected => _LibraryFailure(
      key: const ValueKey('user-library-authentication-error'),
      failure: _controller.failure,
      canRetry: false,
      onRetry: _controller.retry,
      onSignInAgain: widget.onSignInAgain,
    ),
  };
}

class _PlaylistCollection extends StatelessWidget {
  const _PlaylistCollection({
    required this.playlists,
    required this.onSelected,
    super.key,
  });

  final List<UserPlaylistSummary> playlists;
  final ValueChanged<UserPlaylistSummary> onSelected;

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
                'Your playlists',
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
                        itemBuilder: (context, index) => _PlaylistGridItem(
                          playlist: playlists[index],
                          onTap: () => onSelected(playlists[index]),
                        ),
                      )
                    : ListView.separated(
                        itemCount: playlists.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _PlaylistListItem(
                          playlist: playlists[index],
                          onTap: () => onSelected(playlists[index]),
                        ),
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
  const _PlaylistGridItem({required this.playlist, required this.onTap});

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _semanticLabel(playlist),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
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
      ),
    );
  }
}

class _PlaylistListItem extends StatelessWidget {
  const _PlaylistListItem({required this.playlist, required this.onTap});

  final UserPlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _semanticLabel(playlist),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.playlist});

  final UserPlaylistSummary playlist;

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
    title: 'No playlists yet',
    detail: 'Playlists you create or save in QQ Music will appear here.',
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

  final UserLibraryFailure? failure;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = _failureCopy(failure);
    return _CenteredLibraryMessage(
      icon:
          failure == UserLibraryFailure.credentialRejected ||
              failure ==
                  UserLibraryFailure.credentialRejectedStorageCleanupFailed
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

(String, String) _failureCopy(UserLibraryFailure? failure) => switch (failure) {
  UserLibraryFailure.network => (
    'Couldn’t reach QQ Music',
    'Your session is still active. Check your connection and try again.',
  ),
  UserLibraryFailure.serviceUnavailable => (
    'QQ Music is unavailable',
    'Your session was kept unchanged. Try loading your playlists again later.',
  ),
  UserLibraryFailure.invalidResponse => (
    'Couldn’t read the complete library',
    'QQ Music returned a collection this build could not safely finish. '
        'No partial list is shown.',
  ),
  UserLibraryFailure.credentialRejected => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, so the stored session was removed.',
  ),
  UserLibraryFailure.credentialRejectedStorageCleanupFailed => (
    'Your saved session was rejected',
    'QQ Music no longer accepts it, but secure storage could not remove it.',
  ),
  UserLibraryFailure.authenticationRequired ||
  UserLibraryFailure.replaced ||
  UserLibraryFailure.cancelled => (
    'Sign in to load your playlists',
    'The account state changed before this library request finished.',
  ),
  UserLibraryFailure.coreUnavailable => (
    'The music core is unavailable',
    'Your library could not be loaded safely. Try again after restarting.',
  ),
  UserLibraryFailure.alreadyRunning => (
    'A library request is already running',
    'Wait for it to finish, then try again.',
  ),
  null => (
    'Couldn’t load your playlists',
    'Try again or sign in with a fresh QQ Music session.',
  ),
};

String _semanticLabel(UserPlaylistSummary playlist) {
  final count = playlist.trackCount;
  return count == null ? playlist.title : '${playlist.title}, $count tracks';
}
