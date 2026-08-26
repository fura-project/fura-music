import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';

void main() {
  testWidgets('renders truthful bootstrap state', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const bootstrap = BootstrapStatus(
      coreVersion: '0.1.0-test',
      provider: ProviderStatus(
        id: 'qq-music',
        displayName: 'QQ Music',
        implementedCapabilities: ['Authentication'],
      ),
    );

    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: bootstrap,
        authenticationGateway: _WidgetGateway(session),
      ),
    );

    expect(find.text('QQ Music connected'), findsOneWidget);
    expect(find.text('qq-music'), findsOneWidget);
    expect(find.text('0.1.0-test'), findsOneWidget);
    expect(find.text('Continue with WeChat'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with WeChat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Scan with WeChat'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with WeChat'), findsOneWidget);
    expect(session.cancelCalls, 1);
  });

  testWidgets('uses a scrollable single-column layout on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: const BootstrapStatus(
          coreVersion: '0.1.0-test',
          provider: ProviderStatus(
            id: 'qq-music',
            displayName: 'QQ Music',
            implementedCapabilities: ['Authentication'],
          ),
        ),
        authenticationGateway: _WidgetGateway(session),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with WeChat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not present an unverified restored session as signed in', (
    tester,
  ) async {
    final session = _WaitingSession();
    final verification = _PendingWidgetVerification();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          session,
          verificationOperation: verification,
        ),
        initialCredentialRestore: CredentialRestoreResult.verificationRequired,
      ),
    );

    expect(find.text('Checking your saved session…'), findsOneWidget);
    expect(find.text('Use a new code'), findsOneWidget);
    expect(find.text('You’re signed in'), findsNothing);

    verification.complete(CredentialVerificationResult.network);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t reach QQ Music'), findsOneWidget);
    expect(find.text('Try verification again'), findsOneWidget);
    expect(find.text('You’re signed in'), findsNothing);
  });

  testWidgets('shows an explicitly rejected restored session', (tester) async {
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          session,
          verificationOperation: const _ImmediateWidgetVerification(
            CredentialVerificationResult.rejected,
          ),
        ),
        initialCredentialRestore: CredentialRestoreResult.verificationRequired,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved session was rejected'), findsOneWidget);
    expect(find.text('Try verification again'), findsNothing);
    expect(find.text('Sign in again'), findsOneWidget);
  });

  testWidgets('presents a locally expired stored session separately', (
    tester,
  ) async {
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(session),
        initialCredentialRestore: CredentialRestoreResult.locallyExpired,
      ),
    );

    expect(find.text('Saved session expired'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('This code expired'), findsNothing);
  });

  testWidgets('routes an authenticated account into its user playlists', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'owned:7001:201',
                title: 'Synthetic favorites',
                trackCount: 42,
              ),
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:8001',
                title: 'Synthetic saved mix',
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('Your playlists'), findsOneWidget);
    expect(find.text('Synthetic favorites'), findsOneWidget);
    expect(find.text('Synthetic saved mix'), findsOneWidget);
    expect(find.text('42 tracks'), findsOneWidget);
    final playlistSemantics = tester.getSemantics(
      find.text('Synthetic favorites'),
    );
    expect(playlistSemantics.label, 'Synthetic favorites, 42 tracks');
    expect(
      playlistSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    expect(find.text('You’re signed in'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes fresh QR authentication into the library', (
    tester,
  ) async {
    final session = _WaitingSession();
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(session),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
      ),
    );

    await tester.ensureVisible(find.text('Continue with WeChat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with WeChat'));
    await tester.pump();
    session.complete(
      const LoginUpdate(
        progress: LoginProgress.authenticated,
        sessionActive: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('routes verified startup restore into the library', (
    tester,
  ) async {
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          verificationOperation: const _ImmediateWidgetVerification(
            CredentialVerificationResult.authenticated,
          ),
        ),
        libraryGateway: _WidgetLibraryGateway([const UserLibraryResult()]),
        initialCredentialRestore: CredentialRestoreResult.verificationRequired,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your music'), findsOneWidget);
    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('renders user playlists without overflow on a narrow screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'owned:7002:202',
                title: 'Narrow playlist',
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Narrow playlist'), findsOneWidget);
    final playlistSemantics = tester.getSemantics(find.text('Narrow playlist'));
    expect(playlistSemantics.label, 'Narrow playlist');
    expect(
      playlistSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens an adaptive playlist detail and returns to the library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detailGateway = _WidgetDetailGateway([
      const PlaylistTrackPageResult(
        total: 2,
        hasMore: true,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:1:opaque-mid',
            title: 'Synthetic track',
            subtitle: 'Fixture version',
            artistNames: ['Artist one', 'Artist two'],
            albumTitle: 'Synthetic album',
            durationSeconds: 245,
          ),
        ],
      ),
      const PlaylistTrackPageResult(
        offset: 1,
        total: 2,
        tracks: [
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41002:0:1:second-mid',
            title: 'Second synthetic track',
            artistNames: ['Artist three'],
            durationSeconds: 120,
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            playlists: [
              UserPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'favorite:8001',
                title: 'Open me',
                trackCount: 2,
              ),
            ],
          ),
        ]),
        playlistDetailGateway: detailGateway,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open me').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Synthetic track'), findsOneWidget);
    expect(find.textContaining('Artist one'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
    expect(find.text('Showing 1 of 2 tracks'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
    expect(detailGateway.requests.single.playlist.opaqueId, 'favorite:8001');
    expect(detailGateway.requests.single.offset, 0);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Second synthetic track'), findsOneWidget);
    expect(find.text('Showing 2 of 2 tracks'), findsOneWidget);
    expect(find.text('End of playlist'), findsOneWidget);
    expect(detailGateway.requests[1].offset, 1);

    await tester.tap(find.byTooltip('Back to playlists'));
    await tester.pumpAndSettle();
    expect(find.text('Your playlists'), findsOneWidget);
  });

  testWidgets('retries a transient library failure', (tester) async {
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(failure: UserLibraryFailure.network),
          const UserLibraryResult(),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t reach QQ Music'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('returns rejected library credentials to sign-in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MusicApp(
        bootstrap: _bootstrap,
        authenticationGateway: _WidgetGateway(
          _WaitingSession(),
          authenticated: true,
        ),
        libraryGateway: _WidgetLibraryGateway([
          const UserLibraryResult(
            failure: UserLibraryFailure.credentialRejected,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your saved session was rejected'), findsOneWidget);
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with WeChat'), findsOneWidget);
  });
}

const _bootstrap = BootstrapStatus(
  coreVersion: '0.1.0-test',
  provider: ProviderStatus(
    id: 'qq-music',
    displayName: 'QQ Music',
    implementedCapabilities: ['Authentication'],
  ),
);

class _WidgetGateway implements QqMusicAuthenticationGateway {
  _WidgetGateway(
    this.session, {
    this.authenticated = false,
    CredentialVerificationOperation? verificationOperation,
  }) : _verificationOperation =
           verificationOperation ??
           const _ImmediateWidgetVerification(
             CredentialVerificationResult.noRestoredCredential,
           );

  final _WaitingSession session;
  final bool authenticated;
  final CredentialVerificationOperation _verificationOperation;

  @override
  bool get hasAuthenticatedCredential => authenticated;

  @override
  LoginStartOperation beginStart() => _WidgetStartOperation(
    LoginStart(
      session: session,
      challenge: LoginChallenge(
        imageFormat: LoginImageFormat.png,
        imageBytes: Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
            'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      ),
    ),
  );

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      _verificationOperation;

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async =>
      CredentialPersistenceResult.stored;

  @override
  Future<CredentialRestoreResult> restoreCredential() async =>
      CredentialRestoreResult.signedOut;
}

class _WidgetLibraryGateway implements UserLibraryGateway {
  _WidgetLibraryGateway(this.results);

  final List<UserLibraryResult> results;
  int _next = 0;

  @override
  UserLibraryLoadOperation beginLoad() =>
      _WidgetLibraryOperation(results[_next++]);
}

class _WidgetLibraryOperation implements UserLibraryLoadOperation {
  const _WidgetLibraryOperation(this.result);

  final UserLibraryResult result;

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => result;
}

class _DetailRequest {
  const _DetailRequest(this.playlist, this.offset, this.size);
  final UserPlaylistSummary playlist;
  final int offset;
  final int size;
}

class _WidgetDetailGateway implements PlaylistDetailGateway {
  _WidgetDetailGateway(this.results);

  final List<PlaylistTrackPageResult> results;
  final List<_DetailRequest> requests = [];
  int _next = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requests.add(_DetailRequest(playlist, offset, size));
    return _WidgetDetailOperation(results[_next++]);
  }
}

class _WidgetDetailOperation implements PlaylistTrackPageLoadOperation {
  const _WidgetDetailOperation(this.result);
  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => result;
}

class _WidgetStartOperation implements LoginStartOperation {
  const _WidgetStartOperation(this.result);

  final LoginStart result;

  @override
  bool cancel() => true;

  @override
  Future<LoginStart> run() async => result;
}

class _ImmediateWidgetVerification implements CredentialVerificationOperation {
  const _ImmediateWidgetVerification(this.result);

  final CredentialVerificationResult result;

  @override
  bool cancel() => true;

  @override
  Future<CredentialVerificationResult> run() async => result;
}

class _PendingWidgetVerification implements CredentialVerificationOperation {
  final Completer<CredentialVerificationResult> _result =
      Completer<CredentialVerificationResult>();

  @override
  bool cancel() => true;

  @override
  Future<CredentialVerificationResult> run() => _result.future;

  void complete(CredentialVerificationResult result) =>
      _result.complete(result);
}

class _WaitingSession implements LoginSession {
  final Completer<LoginUpdate> _advance = Completer<LoginUpdate>();
  bool _active = true;
  int cancelCalls = 0;

  @override
  bool get isActive => _active;

  @override
  Future<LoginUpdate> advance() => _advance.future;

  void complete(LoginUpdate update) {
    _active = update.sessionActive;
    _advance.complete(update);
  }

  @override
  bool cancel() {
    cancelCalls += 1;
    final wasActive = _active;
    _active = false;
    return wasActive;
  }
}
