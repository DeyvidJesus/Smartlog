import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/route_coordinates.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/road_routing_service.dart';
import '../theme/app_theme.dart';

class RoadMap extends StatefulWidget {
  final List<Map<String, dynamic>> stops;
  final LatLng? driver;
  final Future<void> Function(double meters, bool includesGps)? onDistance;
  const RoadMap({super.key, required this.stops, this.driver, this.onDistance});
  @override
  State<RoadMap> createState() => _RoadMapState();
}

class _RoadMapState extends State<RoadMap> {
  final _routing = RoadRoutingService();
  GoogleMapController? _map;
  Timer? _timer;
  int _generation = 0;
  bool _loading = true;
  bool _locationAllowed = false;
  String? _error;
  String? _info;
  Set<Marker> _markers = {};
  List<LatLng> _road = [];
  DateTime? _lastCalculation;
  LatLng? _routedFrom;
  String get _signature => jsonEncode(widget.stops
      .map((s) => [
            s['docId'],
            s['endereco'],
            s['latitude'],
            s['longitude'],
            s['status'],
            s['ordemEntrega']
          ])
      .toList());

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _calculate();
  }

  Future<void> _checkPermission() async {
    final p = await Geolocator.checkPermission();
    if (mounted) {
      setState(() => _locationAllowed =
          p == LocationPermission.always || p == LocationPermission.whileInUse);
    }
  }

  @override
  void didUpdateWidget(covariant RoadMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStops = jsonEncode(oldWidget.stops
        .map((s) => [
              s['docId'],
              s['endereco'],
              s['latitude'],
              s['longitude'],
              s['status'],
              s['ordemEntrega']
            ])
        .toList());
    if (oldStops != _signature) {
      _timer?.cancel();
      _road = [];
      _calculate();
    } else if (widget.driver != oldWidget.driver && widget.driver != null) {
      final from = _routedFrom;
      if (from != null &&
          Geolocator.distanceBetween(from.latitude, from.longitude,
                  widget.driver!.latitude, widget.driver!.longitude) <
              50) {
        return;
      }
      final elapsed = _lastCalculation == null
          ? 30
          : DateTime.now().difference(_lastCalculation!).inSeconds;
      _timer ??= Timer(Duration(seconds: math.max(0, 30 - elapsed)), () {
        _timer = null;
        if (mounted) _calculate();
      });
    }
  }

  Future<void> _calculate() async {
    final generation = ++_generation;
    _lastCalculation = DateTime.now();
    final stops = List<Map<String, dynamic>>.from(widget.stops);
    final driver = widget.driver;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
      _road = [];
    });
    try {
      final points = <LatLng>[];
      final markers = <Marker>{};
      for (var i = 0; i < stops.length; i++) {
        final point = await resolveRouteStop(stops[i]);
        if (!mounted || generation != _generation) return;
        points.add(point);
        markers.add(Marker(
            markerId: MarkerId(stops[i]['docId']?.toString() ?? 'stop-$i'),
            position: point,
            infoWindow: InfoWindow(
                title: stops[i]['id']?.toString() ?? 'Parada ${i + 1}',
                snippet: stops[i]['endereco']?.toString()),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange)));
      }
      if (driver != null) {
        markers.add(Marker(
            markerId: const MarkerId('gps-driver'),
            position: driver,
            infoWindow:
                const InfoWindow(title: 'Último GPS enviado pelo motorista'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure)));
      }
      final via = <LatLng>[if (driver != null) driver, ...points];
      if (!mounted || generation != _generation) return;
      setState(() => _markers = markers);
      if (via.length < 2) {
        setState(() => _info = via.isEmpty
            ? 'Nenhuma parada para esta rota.'
            : 'Aguardando GPS ou outra parada para calcular o trajeto.');
        await _fit(via);
        return;
      }
      final result = await _routing.route(via);
      if (!mounted || generation != _generation) return;
      setState(() {
        _road = result.points;
        _routedFrom = driver;
        _info =
            '${(result.meters / 1000).toStringAsFixed(1)} km pelas ruas • sem trânsito ao vivo';
      });
      if (widget.onDistance != null) {
        try { await widget.onDistance!(result.meters, driver != null); }
        catch (_) { if (mounted) setState(() => _info = 'Trajeto calculado; distância não sincronizada. Atualize para tentar novamente.'); }
      }
      await _fit(via);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _road = [];
          _error =
              'Não foi possível calcular pelas ruas. Confira os endereços e a conexão.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _fit(List<LatLng> points) async {
    if (_map == null || points.isEmpty) return;
    if (points.length == 1) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }
    final south = points.map((p) => p.latitude).reduce(math.min),
        north = points.map((p) => p.latitude).reduce(math.max);
    final west = points.map((p) => p.longitude).reduce(math.min),
        east = points.map((p) => p.longitude).reduce(math.max);
    await _map!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(south - 0.0001, west - 0.0001),
            northeast: LatLng(north + 0.0001, east + 0.0001)),
        35));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    _routing.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: GoogleMap(
                initialCameraPosition: CameraPosition(
                    target: widget.driver ?? const LatLng(-23.5505, -46.6333),
                    zoom: 12),
                onMapCreated: (map) {
                  _map = map;
                  _fit(_markers.map((m) => m.position).toList());
                },
                markers: {
                  ..._markers.where((m) => m.markerId.value != 'gps-driver'),
                  if (widget.driver != null)
                    Marker(
                        markerId: const MarkerId('gps-driver'),
                        position: widget.driver!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure),
                        infoWindow: const InfoWindow(
                            title: 'Último GPS enviado pelo motorista'))
                },
                polylines: {
                  if (_road.isNotEmpty)
                    Polyline(
                        polylineId: const PolylineId('road-route'),
                        points: _road,
                        color: AppTheme.accentOrange,
                        width: 5)
                },
                myLocationEnabled: _locationAllowed,
                myLocationButtonEnabled: _locationAllowed,
                zoomControlsEnabled: false)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(children: [
              Expanded(
                  child: Text(
                      _loading
                          ? 'Calculando pelas ruas…'
                          : _error ?? _info ?? '',
                      style: TextStyle(
                          fontSize: 11,
                          color: _error != null
                              ? Colors.red
                              : AppTheme.primaryDark))),
              IconButton(
                  tooltip: 'Atualizar trajeto',
                  onPressed: _loading ? null : _calculate,
                  icon: const Icon(Icons.refresh, size: 19)),
            ])),
        InkWell(
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/')),
            child: const Padding(
                padding: EdgeInsets.only(bottom: 3),
                child: Text('Trajeto: OSRM / © OpenStreetMap • corrigir mapa',
                    style: TextStyle(fontSize: 10)))),
      ]);
}
