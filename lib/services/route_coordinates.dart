import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
final _routeAddresses = <String, LatLng>{};
Future<LatLng> resolveRouteStop(Map<String, dynamic> stop) async {
    final lat = stop['latitude'], lng = stop['longitude'];
    if (lat is num &&
        lng is num &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    final address =
        (stop['endereco'] ?? stop['destino'] ?? '').toString().trim();
    if (address.isEmpty) {
      throw Exception('Uma parada não possui endereço ou coordenadas.');
    }
    final cached = _routeAddresses[address];
    if (cached != null) return cached;
    final locations = await Geocoding()
        .locationFromAddress(address)
        .timeout(const Duration(seconds: 15));
    if (locations.isEmpty) throw Exception('Endereço não localizado: $address');
    final point = LatLng(locations.first.latitude, locations.first.longitude);
    _routeAddresses[address] = point;
    return point;
  }

