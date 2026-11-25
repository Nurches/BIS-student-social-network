import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

/// Builds the image of a poster from its absolute URL. A provider, so widget
/// tests can show a picture without the network.
final posterImageProvider = Provider<ImageProvider Function(String url)>(
  (ref) =>
      (url) => NetworkImage(url),
);

/// `poster_url` of the Event object is a path on the API host
/// (`/api/v1/events/7/poster?v=…`); the host comes from `API_BASE_URL`.
String? absolutePosterUrl(AppConfig config, String? path) {
  if (path == null || path.isEmpty) return null;
  final parsed = Uri.tryParse(path);
  if (parsed == null) return null;
  if (parsed.hasScheme) return path;
  final base = Uri.tryParse(config.apiBaseUrl);
  if (base == null || !base.hasScheme) return null;
  return base.resolveUri(parsed).toString();
}

/// Week 13 (FR-08): the event's poster, cropped to fill its box. While it
/// loads, and if it cannot be loaded (no connection, removed), [fallback] —
/// the community's colours — is shown, so a card never looks broken.
class PosterImage extends ConsumerWidget {
  const PosterImage({
    required this.path,
    required this.fallback,
    this.semanticLabel,
    super.key,
  });

  final String? path;
  final Widget fallback;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = absolutePosterUrl(ref.watch(appConfigProvider), path);
    if (url == null) return fallback;
    final image = Image(
      key: ValueKey(url),
      image: ref.watch(posterImageProvider)(url),
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        if (synchronous || frame != null) return child;
        return fallback;
      },
      errorBuilder: (context, error, stack) => fallback,
    );
    // The label is there while the picture loads too.
    final label = semanticLabel;
    return label == null
        ? image
        : Semantics(label: label, image: true, child: image);
  }
}

/// A dark gradient over a poster, so white text on top stays readable
/// whatever the picture is.
class PosterScrim extends StatelessWidget {
  const PosterScrim({super.key, this.top = 0.25, this.bottom = 0.92});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      // Darkest where the text is: text printed on the poster itself must
      // not compete with the title of the card.
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.5, 1],
        colors: [
          Colors.black.withValues(alpha: top),
          Colors.black.withValues(alpha: bottom - 0.04),
          Colors.black.withValues(alpha: bottom),
        ],
      ),
    ),
  );
}
