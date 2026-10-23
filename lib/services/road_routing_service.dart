import 'dart:async';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RoadRoute {
  final List<LatLng> points;
  final double meters;
  RoadRoute(this.points, this.meters);
}

/// Road geometry, never a straight-line substitute. Public service for the demo.
class RoadRoutingService {
  final http.Client _client;
  RoadRoutingService({http.Client? client}) : _client = client ?? http.Client();
  static Future<void> _queue = Future.value();
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const endpoint = String.fromEnvironment('ROUTING_URL',
      defaultValue:
          'https://routing.openstreetmap.de/routed-car/route/v1/driving');
  final Map<String, RoadRoute> _cache = {};

  Future<RoadRoute> route(List<LatLng> stops) async {
    if (stops.length < 2 || stops.length > 25) {
      throw Exception('Selecione entre 2 e 25 pontos para calcular o trajeto.');
    }
    if (stops.any((p) =>
        !p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180)) {
      throw Exception('Uma parada possui coordenadas inválidas.');
    }
    final coordinates =
        stops.map((p) => '${p.longitude},${p.latitude}').join(';');
    final cached = _cache[coordinates];
    if (cached != null) return cached;
    final ready = Completer<void>();
    final previous = _queue;
    _queue = ready.future;
    try {
      await previous;
      final delay =
          1100 - DateTime.now().difference(_lastRequest).inMilliseconds;
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      _lastRequest = DateTime.now();
      final uri = Uri.parse('$endpoint/$coordinates').replace(queryParameters: {
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
      });
      final response = await _client.get(uri, headers: {
        'User-Agent':
            'SmartLog-NEXT-Demo/1.0 (+https://smartlog-next-2026.netlify.app)',
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Serviço de trajetos indisponível. Tente atualizar.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (data['code'] != 'Ok' || routes == null || routes.isEmpty) {
        throw Exception(
            'Não foi encontrado um trajeto pelas ruas para estas paradas.');
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final raw = geometry?['coordinates'] as List?;
      if (geometry?['type'] != 'LineString' || raw == null || raw.length < 2) {
        throw Exception('O serviço não retornou um trajeto válido.');
      }
      final points = raw.map((value) {
        if (value is! List ||
            value.length < 2 ||
            value[0] is! num ||
            value[1] is! num) {
          throw const FormatException('Coordenadas inválidas na resposta.');
        }
        final point =
            LatLng((value[1] as num).toDouble(), (value[0] as num).toDouble());
        if (!(value[0] as num).isFinite ||
            !(value[1] as num).isFinite ||
            (value[0] as num).abs() > 180 ||
            (value[1] as num).abs() > 90) {
          throw const FormatException('Coordenadas inválidas na resposta.');
        }
        return point;
      }).toList();
      final result =
          RoadRoute(points, (route['distance'] as num?)?.toDouble() ?? 0);
      if (_cache.length >= 20) _cache.remove(_cache.keys.first);
      _cache[coordinates] = result;
      return result;
    } finally {
      ready.complete();
    }
  }

  void dispose() => _client.close();
}
