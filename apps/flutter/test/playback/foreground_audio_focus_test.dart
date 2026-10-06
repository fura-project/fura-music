import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';

const deadline = Duration(milliseconds: 20);
const watchdog = Duration(milliseconds: 300);
final unavailable = isA<ForegroundAudioException>().having(
  (error) => error.failure,
  'failure',
  ForegroundAudioFailure.coreUnavailable,
);

void main() {
  test('release revokes an activation waiting for native quiescence before acquisition', () async {
    final control = Completer<void>();
    final manager = _Focus();
    final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
    final lease = owner.createLease();
    await lease.activate();
    final pausing = lease.releaseAfter(() => control.future);
    final activating = expectLater(lease.activate(), throwsA(unavailable));
    await lease.release();
    control.complete();
    await pausing;
    await activating;
    expect(manager.calls, [true, false]);
    expect(lease.isActive, isFalse);
    await lease.close();
  });

  test(
    'pause failure is observed before a waiting activation, and releases focus',
    () async {
      final control = Completer<void>();
      final manager = _Focus();
      final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
      final lease = owner.createLease();
      await lease.activate();
      final releasing = expectLater(
        lease.releaseAfter(() => control.future),
        throwsA(unavailable),
      );
      final activating = expectLater(lease.activate(), throwsA(unavailable));
      control.completeError(
        const ForegroundAudioException(ForegroundAudioFailure.coreUnavailable),
      );
      await Future.wait([releasing, activating]);
      expect(manager.calls, [true, false]);
      expect(lease.isActive, isFalse);
      await lease.close();
    },
  );

  test(
    'a failed release never lets a waiting resume reclaim uncertain focus',
    () async {
      final control = Completer<void>();
      final manager = _Focus();
      final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
      final lease = owner.createLease();
      await lease.activate();
      manager.allowRelease = false;
      final releasing = expectLater(
        lease.releaseAfter(() => control.future),
        throwsA(unavailable),
      );
      final activating = expectLater(lease.activate(), throwsA(unavailable));
      control.complete();
      await Future.wait([releasing, activating]);
      await expectLater(lease.activate(), throwsA(unavailable));
      expect(manager.calls, [true, false]);
    },
  );

  test('late old native pause cannot release a replacement lease', () async {
    final control = Completer<void>();
    final manager = _Focus();
    final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
    final old = owner.createLease();
    final next = owner.createLease();
    await old.activate();
    final releasing = old.releaseAfter(() => control.future);
    final activating = expectLater(old.activate(), throwsA(unavailable));
    await old.close();
    expect(await next.activate(), isTrue);
    control.complete();
    await releasing;
    await activating;
    expect(next.isActive, isTrue);
    expect(manager.calls, [true, false, true]);
    await next.close();
  });

  test(
    'activation timeout compensates late success before a new lease',
    () async {
      final activation = Completer<bool>();
      final release = Completer<bool>();
      final manager = _Focus()
        ..activate = activation.future
        ..release = release.future;
      final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
      final old = owner.createLease();
      final next = owner.createLease();
      await expectLater(old.activate().timeout(watchdog), throwsA(unavailable));
      await expectLater(next.activate(), throwsA(unavailable));
      expect(manager.calls, [true]);
      activation.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(manager.calls, [true, false]);
      await expectLater(next.activate(), throwsA(unavailable));
      manager.activate = null;
      release.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(await next.activate(), isTrue);
      await old.close();
      expect(manager.calls, [true, false, true]);
      await next.close();
    },
  );

  test(
    'pending release stays reserved after timeout and stale cleanup is inert',
    () async {
      final release = Completer<bool>();
      final manager = _Focus()..release = release.future;
      final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
      final old = owner.createLease();
      final next = owner.createLease();
      expect(await old.activate(), isTrue);
      await expectLater(old.release().timeout(watchdog), throwsA(unavailable));
      await expectLater(old.activate(), throwsA(unavailable));
      await expectLater(next.activate(), throwsA(unavailable));
      await expectLater(old.close().timeout(watchdog), throwsA(unavailable));
      expect(manager.calls, [
        true,
        false,
      ], reason: 'no duplicate cleanup/retry');
      release.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(await next.activate(), isTrue);
      await old.release();
      expect(next.isActive, isTrue);
      expect(manager.calls, [true, false, true]);
      await next.close();
    },
  );

  test(
    'concurrent acquisition is single-flight and close revokes it',
    () async {
      final activation = Completer<bool>();
      final manager = _Focus()..activate = activation.future;
      final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
      final lease = owner.createLease();
      final a = expectLater(lease.activate(), throwsA(unavailable));
      final b = expectLater(lease.activate(), throwsA(unavailable));
      final closing = expectLater(lease.close(), throwsA(unavailable));
      activation.complete(true);
      await Future.wait([a, b, closing]);
      expect(manager.calls, [true, false]);
      expect(lease.isActive, isFalse);
      await expectLater(lease.activate(), throwsA(unavailable));
    },
  );

  test(
    'denied activation is not an unknown ownership or an extra release',
    () async {
      final manager = _Focus()..allowActivation = false;
      final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
      final old = owner.createLease();
      expect(await old.activate(), isFalse);
      await old.close();
      expect(manager.calls, [true]);
      manager.allowActivation = true;
      final next = owner.createLease();
      expect(await next.activate(), isTrue);
      await next.close();
    },
  );

  for (final throws in [false, true]) {
    test(
      'unconfirmed release fails closed (throws=$throws), without retry',
      () async {
        final manager = _Focus();
        final messages = <String>[];
        final previous = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) messages.add(message);
        };
        addTearDown(() => debugPrint = previous);
        final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
        final old = owner.createLease();
        expect(await old.activate(), isTrue);
        if (throws) {
          manager.releaseError = StateError(
            'https://private.test/?token=synthetic',
          );
        } else {
          manager.allowRelease = false;
        }
        await expectLater(old.release(), throwsA(unavailable));
        await expectLater(owner.createLease().activate(), throwsA(unavailable));
        await expectLater(old.activate(), throwsA(unavailable));
        await expectLater(old.close(), throwsA(unavailable));
        expect(manager.calls, [true, false]);
        final trace = messages.join('\n');
        expect(trace, contains('phase=release'));
        expect(trace, contains('outcome=unconfirmed'));
        for (final secret in ['private.test', 'token', 'synthetic', 'https:']) {
          expect(trace, isNot(contains(secret)));
        }
      },
    );
  }

  test('activation exception is compensated before another request', () async {
    final manager = _Focus()..activationError = StateError('private');
    final owner = ForegroundAudioFocusOwner(manager, timeout: deadline);
    await expectLater(owner.createLease().activate(), throwsA(unavailable));
    expect(manager.calls, [true, false]);
    manager.activationError = null;
    final next = owner.createLease();
    expect(await next.activate(), isTrue);
    await next.close();
  });
}

class _Focus implements ForegroundAudioFocusManager {
  final calls = <bool>[];
  Future<bool>? activate;
  Future<bool>? release;
  Object? activationError;
  Object? releaseError;
  bool allowActivation = true;
  bool allowRelease = true;
  @override
  Future<bool> setActive(bool active) async {
    calls.add(active);
    final error = active ? activationError : releaseError;
    if (error != null) throw error;
    return await (active ? activate : release) ??
        (active ? allowActivation : allowRelease);
  }
}
