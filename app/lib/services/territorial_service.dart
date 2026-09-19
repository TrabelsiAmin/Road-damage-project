import 'package:geolocator/geolocator.dart';

class TerritorialMatch {
  const TerritorialMatch({required this.routeName, required this.segment, required this.owner});
  final String routeName;
  final String segment;
  final String owner;
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

/// Temporary deterministic boundary until the SIG road network is connected.
/// Production must replace this with a backend or offline spatial index.
class TerritorialService {
  TerritorialMatch match({required double latitude, required double longitude}) {
    final owner = latitude > 36.5 ? 'Ministry of Equipment' : 'Municipality';
    return TerritorialMatch(routeName: 'Unmatched road segment', segment: 'pending SIG match', owner: owner);
  }
}
