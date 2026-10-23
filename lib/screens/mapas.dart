import '../widgets/driver_road_map.dart';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic> rota;
  final String rotaId;
  final String motoristaNome;

  const MapScreen({
    super.key,
    required this.rota,
    required this.rotaId,
    required this.motoristaNome,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _map;

  bool _loading = false;
  bool _styleLoaded = false;

  String? _error;
  String? _routeInfo;

  static const String _token =
  String.fromEnvironment('ACCESS_TOKEN', defaultValue: String.fromEnvironment('MAPBOX_ACCESS_TOKEN'));

  static const String _sourceId = 'delivery-route-source';
  static const String _layerId = 'delivery-route-layer';
  static const String _pointsLayerId = 'delivery-points-layer';

  Position? _currentLocation;
  List<Position>? _stopPositions;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _rotaSubscription;

  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();

    if (_token.isEmpty) {
      _error = 'Token do Mapbox não configurado.';
      debugPrint('MAPBOX ERRO: ACCESS_TOKEN está vazio.');
      return;
    }

    MapboxOptions.setAccessToken(_token);
    _listenToDriverLocation();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _rotaSubscription?.cancel();
    super.dispose();
  }

  void _listenToDriverLocation() {
    _rotaSubscription = FirebaseFirestore.instance
        .collection('rotas')
        .doc(widget.rotaId)
        .snapshots()
        .listen(
          (snapshot) {
        if (!snapshot.exists) {
          debugPrint(
            'FIRESTORE: rota ${widget.rotaId} não encontrada.',
          );
          return;
        }

        final data = snapshot.data();
        final loc = data?['localizacaoAtual'];

        if (loc is Map) {
          final lat = loc['latitude'];
          final lng = loc['longitude'];

          if (lat is num && lng is num) {
            _currentLocation = Position(
              lng.toDouble(),
              lat.toDouble(),
            );

            debugPrint(
              'GPS recebido: latitude=$lat, longitude=$lng',
            );

            _scheduleRouteUpdate();
          } else {
            debugPrint(
              'FIRESTORE: latitude/longitude inválidas.',
            );
          }
        } else {
          debugPrint(
            'FIRESTORE: campo localizacaoAtual ausente '
                'ou em formato inesperado.',
          );
        }
      },
      onError: (Object error) {
        debugPrint('FIRESTORE ERRO: $error');

        if (!mounted) return;

        setState(() {
          _error = 'Erro ao acompanhar localização: $error';
        });
      },
    );
  }

  void _scheduleRouteUpdate() {
    _updateTimer?.cancel();

    _updateTimer = Timer(
      const Duration(seconds: 5),
          () {
        if (_styleLoaded && mounted && !_loading) {
          _calculateRoute();
        }
      },
    );
  }


  Future<void> _onMapCreated(MapboxMap map) async {
    debugPrint('MAPBOX: mapa criado.');
    _map = map;

    await map.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(-46.6333, -23.5505),
        ),
        zoom: 11.0,
      ),
    );
  }


  Future<void> _onStyleLoaded(
      StyleLoadedEventData event,
      ) async {
    debugPrint('MAPBOX: estilo carregado.');

    _styleLoaded = true;

    if (mounted) {
      setState(() {
        _error = null;
      });
    }

    await _calculateRoute();
  }

  Future<Position> _geocodeAddress(String address) async {
    final url = Uri.https(
      'api.mapbox.com',
      '/search/geocode/v6/forward',
      {
        'q': address,
        'access_token': _token,
        'limit': '1',
      },
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Falha ao localizar "$address" '
            '(HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final data =
    jsonDecode(response.body) as Map<String, dynamic>;

    final features = data['features'] as List<dynamic>?;

    if (features == null || features.isEmpty) {
      throw Exception(
        'Endereço não encontrado: $address. '
            'Inclua rua, número, cidade e estado.',
      );
    }

    final feature = features.first as Map<String, dynamic>;
    final geometry =
    feature['geometry'] as Map<String, dynamic>;
    final coordinates =
    geometry['coordinates'] as List<dynamic>;

    return Position(
      (coordinates[0] as num).toDouble(),
      (coordinates[1] as num).toDouble(),
    );
  }

  Future<List<Position>> _loadStopPositions() async {
    final rawStops = widget.rota['enderecos'];

    if (rawStops is! List || rawStops.isEmpty) {
      throw Exception(
        'Esta rota não possui endereços de entrega.',
      );
    }

    final positions = <Position>[];

    for (final item in rawStops) {
      if (item is! Map) continue;

      final address =
          item['endereco']?.toString().trim() ?? '';

      if (address.isEmpty) continue;

      positions.add(await _geocodeAddress(address));
    }

    if (positions.isEmpty) {
      throw Exception(
        'Não foi possível localizar os endereços da rota.',
      );
    }

    return positions;
  }

  Future<void> _calculateRoute() async {
    if (_map == null || !_styleLoaded || _loading) return;

    if (_token.isEmpty) {
      if (!mounted) return;

      setState(() {
        _error = 'Token do Mapbox não configurado.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _stopPositions ??= await _loadStopPositions();

      if (!mounted) return;

      final hasDriverLocation = _currentLocation != null;

      final positions = <Position>[
        if (hasDriverLocation) _currentLocation!,
        ..._stopPositions!,
      ];

      String? routeInfo;
      List<dynamic>? routeCoordinates;

      if (positions.length >= 2) {
        final coordinates = positions
            .map((p) => '${p.lng},${p.lat}')
            .join(';');

        final url = Uri.https(
          'api.mapbox.com',
          '/directions/v5/mapbox/driving/$coordinates',
          {
            'access_token': _token,
            'geometries': 'geojson',
            'overview': 'full',
            'steps': 'false',
          },
        );

        final response = await http.get(url);

        if (response.statusCode != 200) {
          throw Exception(
            'Falha ao calcular o trajeto '
                '(HTTP ${response.statusCode}): ${response.body}',
          );
        }

        final data =
        jsonDecode(response.body) as Map<String, dynamic>;

        final routes = data['routes'] as List<dynamic>?;

        if (routes == null || routes.isEmpty) {
          throw Exception(
            'O Mapbox não encontrou um trajeto para os pontos.',
          );
        }

        final route = routes.first as Map<String, dynamic>;
        final geometry =
        route['geometry'] as Map<String, dynamic>;

        routeCoordinates =
        geometry['coordinates'] as List<dynamic>;

        final distance = (route['distance'] as num?) ?? 0;
        final duration = (route['duration'] as num?) ?? 0;

        routeInfo =
        '${(distance / 1000).toStringAsFixed(1)} km'
            ' • ${(duration / 60).round()} min estimados';
      }

      final features = <Map<String, dynamic>>[];

      if (routeCoordinates != null) {
        features.add({
          'type': 'Feature',
          'properties': {'kind': 'route'},
          'geometry': {
            'type': 'LineString',
            'coordinates': routeCoordinates,
          },
        });
      }

      for (var i = 0; i < positions.length; i++) {
        final position = positions[i];

        features.add({
          'type': 'Feature',
          'properties': {
            'kind': hasDriverLocation && i == 0
                ? 'motorista'
                : 'entrega',
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [
              position.lng,
              position.lat,
            ],
          },
        });
      }

      final geoJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': features,
      });

      final map = _map!;

      try {
        await map.style.removeStyleLayer(_pointsLayerId);
      } catch (_) {}

      try {
        await map.style.removeStyleLayer(_layerId);
      } catch (_) {}

      try {
        await map.style.removeStyleSource(_sourceId);
      } catch (_) {}

      await map.style.addSource(
        GeoJsonSource(
          id: _sourceId,
          data: geoJson,
        ),
      );

      if (routeCoordinates != null) {
        await map.style.addLayer(
          LineLayer(
            id: _layerId,
            sourceId: _sourceId,
            lineColor: Colors.blue.toARGB32(),
            lineWidth: 5.0,
            lineCap: LineCap.ROUND,
            lineJoin: LineJoin.ROUND,
          ),
        );
      }

      await map.style.addLayer(
        CircleLayer(
          id: _pointsLayerId,
          sourceId: _sourceId,
          circleRadius: 7.0,
          circleColor: Colors.deepOrange.toARGB32(),
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.toARGB32(),
        ),
      );

      await map.setCamera(
        CameraOptions(
          center: Point(
            coordinates: positions.first,
          ),
          zoom: 12.0,
        ),
      );

      if (!mounted) return;

      setState(() {
        _routeInfo = routeInfo;
      });

      debugPrint('MAPBOX: rota desenhada com sucesso.');
    } catch (e, stackTrace) {
      debugPrint('ROTA ERRO: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _error = 'Não foi possível carregar a rota: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_token.isEmpty) {
      return RoadRouteScreen(routeId: widget.rotaId,
        tenant: widget.rota['empresaId']?.toString() ?? '',
        title: 'Rota: ${widget.motoristaNome}');
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Rota: ${widget.motoristaNome}'),
      ),
      body: Stack(
        children: [

          MapWidget(
            styleUri: MapboxStyles.STANDARD,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.rota['nome']?.toString() ??
                          'Rota de entregas',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _currentLocation == null
                          ? 'Aguardando localização GPS do motorista'
                          : 'Localização GPS recebida',
                    ),
                    if (_routeInfo != null) ...[
                      const SizedBox(height: 6),
                      Text(_routeInfo!),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed:
                      _loading ? null : _calculateRoute,
                      icon: const Icon(Icons.alt_route),
                      label: Text(
                        _loading
                            ? 'Carregando rota...'
                            : 'Atualizar rota',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}