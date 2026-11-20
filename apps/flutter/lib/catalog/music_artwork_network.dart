import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _neteaseArtworkHeaders = <String, String>{
  'Referer': 'https://music.163.com/',
};
const _musicNetworkUserAgent = 'Mozilla/5.0';

/// Installs the HTTP client policy required by public music-provider assets.
///
/// Flutter's [NetworkImage] appends per-image headers with `HttpHeaders.add`.
/// Dart's [HttpClient] already supplies its own User-Agent, so adding another
/// User-Agent produces a combined value that NetEase's artwork CDN rejects
/// with HTTP 403. Setting the client default here and leaving only Referer in
/// the per-image headers produces one User-Agent value on every platform.
void installMusicNetworkHttpPolicy() {
  final current = HttpOverrides.current;
  if (current is _MusicNetworkHttpOverrides) {
    return;
  }
  HttpOverrides.global = _MusicNetworkHttpOverrides(current);
}

class _MusicNetworkHttpOverrides extends HttpOverrides {
  _MusicNetworkHttpOverrides(this.parent);

  final HttpOverrides? parent;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        parent?.createHttpClient(context) ?? super.createHttpClient(context);
    client.userAgent = _musicNetworkUserAgent;
    return client;
  }
}

/// Returns the public HTTP headers required by NetEase's artwork CDN.
///
/// The CDN requires its web origin Referer. The compatible single User-Agent
/// value is installed on the underlying [HttpClient] because [NetworkImage]
/// would otherwise append it to Dart's rejected default value.
Map<String, String>? musicArtworkRequestHeaders(String artworkUri) {
  final uri = Uri.tryParse(artworkUri);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host == 'music.126.net' || host.endsWith('.music.126.net')) {
    return _neteaseArtworkHeaders;
  }
  return null;
}

const _minimumMusicArtworkCacheEntries = 2500;
const _minimumMusicArtworkCacheBytes = 256 << 20;

void _ensureMusicArtworkCachePolicy() {
  final binding = PaintingBinding.instance;
  final cache = binding.imageCache;
  if (cache.maximumSize < _minimumMusicArtworkCacheEntries) {
    cache.maximumSize = _minimumMusicArtworkCacheEntries;
  }
  if (cache.maximumSizeBytes < _minimumMusicArtworkCacheBytes) {
    cache.maximumSizeBytes = _minimumMusicArtworkCacheBytes;
  }
}

/// Creates the provider used by artwork-dependent color extraction and image
/// prefetch so those paths use the same provider-specific HTTP policy as the
/// visible image widgets.
ImageProvider<Object> musicArtworkImageProvider(String artworkUri) {
  _ensureMusicArtworkCachePolicy();
  return NetworkImage(
    artworkUri,
    headers: musicArtworkRequestHeaders(artworkUri),
  );
}

/// Outcome reported by [MusicArtworkPreloadHandle.future].
enum MusicArtworkPreloadOutcome {
  /// The image decoded and is ready in [ImageCache].
  loaded,

  /// Loading or decoding the image failed.
  failed,

  /// The preload was explicitly cancelled before completing.
  cancelled,
}

/// Handle returned by [startMusicArtworkPreload] describing whether the image
/// was already decoded synchronously in [ImageCache] and providing a [future]
/// plus safe cancellation/cleanup.
class MusicArtworkPreloadHandle {
  const MusicArtworkPreloadHandle._(
    this._cancel, {
    required this.readySynchronously,
    required this.future,
  });

  /// `true` when [PaintingBinding.instance.imageCache] already held a decoded
  /// frame and delivered it synchronously during stream subscription.
  final bool readySynchronously;

  /// Completes with [MusicArtworkPreloadOutcome.loaded] when an image frame is
  /// decoded and cached, [MusicArtworkPreloadOutcome.failed] if loading failed,
  /// or [MusicArtworkPreloadOutcome.cancelled] if [cancel] was called first.
  final Future<MusicArtworkPreloadOutcome> future;

  final VoidCallback _cancel;

  /// Detaches the preload listener and disposes any held [ImageInfo] handle.
  void cancel() => _cancel();
}

/// Checks synchronous [ImageCache] readiness for [provider] and, when not yet
/// decoded, warms the cache without reporting unhandled load exceptions.
MusicArtworkPreloadHandle startMusicArtworkPreload(
  ImageProvider<Object> provider,
  ImageConfiguration configuration,
) {
  _ensureMusicArtworkCachePolicy();
  final stream = provider.resolve(configuration);
  final completer = Completer<MusicArtworkPreloadOutcome>();
  var readySynchronously = false;
  var settled = false;
  var listenerRemoved = false;
  ImageInfo? receivedImage;
  late final ImageStreamListener listener;

  void detach() {
    if (listenerRemoved) return;
    listenerRemoved = true;
    receivedImage?.dispose();
    receivedImage = null;
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (ImageInfo info, bool synchronousCall) {
      if (settled) {
        info.dispose();
        return;
      }
      settled = true;
      receivedImage = info;
      if (synchronousCall) {
        readySynchronously = true;
      }
      if (!completer.isCompleted) {
        completer.complete(MusicArtworkPreloadOutcome.loaded);
      }
      // Keep the stream live through the end of the current frame (matching
      // Flutter's precacheImage) so an immediate widget mount subscribes
      // synchronously without re-decoding.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        detach();
      }, debugLabel: 'musicArtworkPreload.removeListener');
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (settled) return;
      settled = true;
      detach();
      if (!completer.isCompleted) {
        completer.complete(MusicArtworkPreloadOutcome.failed);
      }
    },
  );

  stream.addListener(listener);
  return MusicArtworkPreloadHandle._(
    () {
      settled = true;
      detach();
      if (!completer.isCompleted) {
        completer.complete(MusicArtworkPreloadOutcome.cancelled);
      }
    },
    readySynchronously: readySynchronously,
    future: completer.future,
  );
}

/// Produces a log-safe failure summary for physical-device diagnosis.
///
/// Deliberately excludes the path and query because they may contain provider
/// identifiers. The host, scheme and HTTP status are sufficient to distinguish
/// missing transport permission, CDN rejection and image decoding failures.
@visibleForTesting
String musicArtworkFailureDiagnostic(String artworkUri, Object error) {
  final uri = Uri.tryParse(artworkUri);
  final host = uri == null || uri.host.isEmpty ? 'unknown' : uri.host;
  final scheme = uri == null || uri.scheme.isEmpty ? 'unknown' : uri.scheme;
  final status = error is NetworkImageLoadException
      ? error.statusCode.toString()
      : 'unavailable';
  return 'FURA_DIAGNOSTIC artwork_load_failure '
      'host=$host scheme=$scheme status=$status error=${error.runtimeType}';
}

final Set<String> _reportedArtworkFailures = <String>{};
const _maximumReportedArtworkFailures = 32;

/// Keeps the existing UI fallback while emitting one redacted diagnostic per
/// distinct failure shape. This remains active in release builds so Human
/// device review can collect evidence through logcat.
ImageErrorWidgetBuilder musicArtworkErrorBuilder(
  String artworkUri,
  Widget fallback,
) {
  return (context, error, stackTrace) {
    final diagnostic = musicArtworkFailureDiagnostic(artworkUri, error);
    if (_reportedArtworkFailures.length < _maximumReportedArtworkFailures &&
        _reportedArtworkFailures.add(diagnostic)) {
      debugPrint(diagnostic);
    }
    return fallback;
  };
}

/// Smoothly reveals decoded network artwork over [placeholder] while
/// bypassing the transition for warm-cache synchronous hits, already-decoded
/// frames, and reduced-motion accessibility modes.
ImageFrameBuilder musicArtworkFrameBuilder(
  Widget placeholder, {
  Duration duration = const Duration(milliseconds: 120),
}) {
  _ensureMusicArtworkCachePolicy();
  return (context, child, frame, wasSynchronouslyLoaded) {
    final disableAnimations =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (disableAnimations || duration <= Duration.zero) {
      return frame == null ? placeholder : child;
    }
    return _MusicArtworkFrameReveal(
      placeholder: placeholder,
      hasFrame: frame != null,
      wasSynchronouslyLoaded: wasSynchronouslyLoaded,
      duration: duration,
      child: child,
    );
  };
}

class _MusicArtworkFrameReveal extends StatefulWidget {
  const _MusicArtworkFrameReveal({
    required this.placeholder,
    required this.hasFrame,
    required this.wasSynchronouslyLoaded,
    required this.duration,
    required this.child,
  });

  final Widget placeholder;
  final bool hasFrame;
  final bool wasSynchronouslyLoaded;
  final Duration duration;
  final Widget child;

  @override
  State<_MusicArtworkFrameReveal> createState() =>
      _MusicArtworkFrameRevealState();
}

class _MusicArtworkFrameRevealState extends State<_MusicArtworkFrameReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;
  bool _revealing = false;
  bool _tickerEnabled = true;
  bool _suppressRevealThisFrame = false;

  void _ensureController() {
    if (_controller != null) {
      _controller!.duration = widget.duration;
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..addStatusListener(_handleStatus);
    _controller = controller;
    _opacity = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ).drive(Tween<double>(begin: 0.35, end: 1.0));
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _revealing && mounted) {
      setState(() => _revealing = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (!enabled) {
      _controller?.stop();
      _revealing = false;
    } else if (!_tickerEnabled) {
      _suppressRevealThisFrame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _suppressRevealThisFrame = false;
      });
    }
    _tickerEnabled = enabled;
  }

  @override
  void didUpdateWidget(_MusicArtworkFrameReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tickerEnabledNow = TickerMode.valuesOf(context).enabled;
    if (!widget.hasFrame ||
        widget.wasSynchronouslyLoaded ||
        !tickerEnabledNow ||
        !_tickerEnabled ||
        _suppressRevealThisFrame) {
      _controller?.stop();
      _revealing = false;
      return;
    }
    if (!oldWidget.hasFrame && widget.hasFrame) {
      _ensureController();
      _revealing = true;
      _controller!.forward(from: 0);
    } else if (_controller != null) {
      _controller!.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasFrame) {
      return widget.placeholder;
    }
    if (!_revealing || _opacity == null) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(child: widget.placeholder),
        FadeTransition(opacity: _opacity!, child: widget.child),
      ],
    );
  }
}
