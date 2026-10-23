import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'road_map.dart';

Future<void> saveRouteDistance(String id, double meters, bool includesGps) =>
  FirebaseFirestore.instance.collection('rotas').doc(id).update({
    'distanciaRestanteMetros': meters, 'distanciaIncluiGps': includesGps,
    'distanciaCalculadaEm': FieldValue.serverTimestamp(),
  });

LatLng? routeGps(Map<String, dynamic>? route) {
  final gps = route?['localizacaoAtual'];
  if (gps is! Map || gps['latitude'] is! num || gps['longitude'] is! num) {
    return null;
  }
  final lat = (gps['latitude'] as num).toDouble(),
      lng = (gps['longitude'] as num).toDouble();
  return lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180
      ? LatLng(lat, lng)
      : null;
}

List<Map<String, dynamic>> routeStops(
    List<Map<String, dynamic>> deliveries, String id,
    {bool history = false}) {
  final stops = deliveries
      .where((d) =>
          d['rotaId'] == id &&
          (history ||
              !['entregue', 'cancelada', 'cancelado']
                  .contains(d['status']?.toString().toLowerCase())))
      .toList();
  stops.sort((a, b) => ((a['ordemEntrega'] as num?) ?? 99999)
      .compareTo((b['ordemEntrega'] as num?) ?? 99999));
  return stops;
}

class DriverRoadMap extends StatefulWidget {
  final String driverId, tenant;
  final List<Map<String, dynamic>> deliveries;
  const DriverRoadMap(
      {super.key,
      required this.driverId,
      required this.tenant,
      required this.deliveries});
  @override
  State<DriverRoadMap> createState() => _DriverRoadMapState();
}

class _DriverRoadMapState extends State<DriverRoadMap> {
  late final _routes = FirebaseFirestore.instance
      .collection('rotas')
      .where('empresaId', isEqualTo: widget.tenant)
      .where('motoristaId', isEqualTo: widget.driverId)
      .snapshots();
  String? _selected;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _routes,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Não foi possível consultar as rotas.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final routes = snapshot.data!.docs;
            if (routes.isEmpty) {
              return const Center(child: Text('Nenhuma rota atribuída.'));
            }
            final selected =
                routes.where((r) => r.id == _selected).firstOrNull ??
                    routes
                        .where((r) => r.data()['status'] == 'Em Rota')
                        .firstOrNull ??
                    routes
                        .where((r) => r.data()['status'] == 'Pendente')
                        .firstOrNull ??
                    routes.first;
            final data = selected.data();
            return Column(children: [
              SizedBox(
                  height: 42,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButton<String>(
                          isExpanded: true,
                          value: selected.id,
                          underline: const SizedBox.shrink(),
                          items: routes
                              .map((r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text(
                                      r.data()['nome']?.toString() ?? 'Rota',
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selected = value)))),
              Expanded(
                  child: RoadMap(
                      key: ValueKey(selected.id),
                      stops: routeStops(widget.deliveries, selected.id,
                          history: data['status'] == 'Concluida'),
                      driver: routeGps(data),
                      onDistance: (m, gps) => saveRouteDistance(selected.id, m, gps))),
            ]);
          });
}

class RoadRouteScreen extends StatelessWidget {
  final String routeId, tenant, title;
  const RoadRouteScreen(
      {super.key,
      required this.routeId,
      required this.tenant,
      required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('rotas')
              .doc(routeId)
              .snapshots(),
          builder: (context, routeSnapshot) {
            if (routeSnapshot.hasError) {
              return const Center(
                  child: Text('Não foi possível consultar a rota.'));
            }
            if (!routeSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final route = routeSnapshot.data!.data();
            if (route == null) {
              return const Center(child: Text('Rota não encontrada.'));
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('entregas')
                    .where('empresaId', isEqualTo: tenant)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                        child: Text('Não foi possível consultar as entregas.'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final deliveries = snapshot.data!.docs
                      .map((d) => {...d.data(), 'docId': d.id})
                      .toList();
                  return RoadMap(
                      key: ValueKey(routeId),
                      stops: routeStops(deliveries, routeId,
                          history: route['status'] == 'Concluida'),
                      driver: routeGps(route),
                      onDistance: (m, gps) => saveRouteDistance(routeId, m, gps));
                });
          }));
}
