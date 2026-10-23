import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartlife/services/road_routing_service.dart';

void main() {
  const stops = [LatLng(-23.55, -46.63), LatLng(-23.56, -46.64)];
  test('uses full street geometry in longitude/latitude order and caches identical routes', () async {
    var calls = 0;
    final service = RoadRoutingService(client: MockClient((request) async {
      calls++;
      expect(request.url.path, contains('-46.63,-23.55;-46.64,-23.56'));
      expect(request.url.queryParameters['overview'], 'full');
      return http.Response(jsonEncode({'code':'Ok','routes':[{'distance':1200,
        'geometry':{'type':'LineString','coordinates':[[-46.63,-23.55],[-46.635,-23.552],[-46.64,-23.56]]}}]}),200);
    }));
    final result = await service.route(stops);
    expect(result.points.length,3);
    expect(result.points[1],const LatLng(-23.552,-46.635));
    await service.route(stops);
    expect(calls,1);
    service.dispose();
  });
  test('does not replace unavailable routing with a straight line', () async {
    final service = RoadRoutingService(client: MockClient((_) async => http.Response('{"code":"NoRoute","routes":[]}',200)));
    await expectLater(service.route(stops),throwsException);
    service.dispose();
  });
  test('rejects one stop instead of manufacturing a route', () async {
    final service = RoadRoutingService(client: MockClient((_) async => throw StateError('No request expected')));
    await expectLater(service.route([stops.first]),throwsException);
    service.dispose();
  });
}
