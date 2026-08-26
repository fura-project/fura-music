class AlbumSummary {
  const AlbumSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    this.artworkUri,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final String? artworkUri;
}

class ArtistSummary {
  const ArtistSummary({
    required this.providerId,
    required this.opaqueId,
    required this.name,
  });

  final String providerId;
  final String opaqueId;
  final String name;
}
