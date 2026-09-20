import 'package:geolocator/geolocator.dart';

class TerritorialMatch {
  const TerritorialMatch({
    required this.routeName,
    required this.segment,
    required this.owner,
    this.matchQuality = 'pending',
  });

  final String routeName;
  final String segment;
  /// Institution that owns the road, or `unmatched` until SIG enrichment.
  /// Municipalité, Ministère de l'Équipement, and Tunisie Autoroutes are peers.
  final String owner;
  final String matchQuality;

  bool get isMatched => matchQuality == 'high' || matchQuality == 'medium';
}

class LocationService {
  Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are disabled.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for a geolocated observation.');
    }
    return Geolocator.getCurrentPosition();
  }
}

/// Temporary deterministic unmatched stub until the SIG road network is connected.
///
/// Production must replace this with a backend or offline spatial index.
/// A missing GPS must NEVER drop the observation — return unmatched so WP5
/// can enrich later. Do not invent an institutional owner from latitude
/// (that implied a hierarchy the validated conception forbids).
class TerritorialService {
  TerritorialMatch match({
    required double latitude,
    required double longitude,
    bool gpsAvailable = true,
  }) {
    if (!gpsAvailable || (latitude == 0.0 && longitude == 0.0)) {
      return const TerritorialMatch(
        routeName: 'Unmatched — GPS missing',
        segment: 'pending GPS enrichment',
        owner: 'unmatched',
        matchQuality: 'none',
      );
    }
    return const TerritorialMatch(
      routeName: 'Unmatched road segment',
      segment: 'pending SIG match',
      owner: 'unmatched',
      matchQuality: 'pending',
    );
  }
}
