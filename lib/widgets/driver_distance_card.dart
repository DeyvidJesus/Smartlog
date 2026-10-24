import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact operational metric shown on the driver's dashboard.
class DriverDistanceCard extends StatelessWidget {
  final String driverId;
  final String tenant;
  final List<Map<String, dynamic>> deliveries;

  const DriverDistanceCard({
    super.key,
    required this.driverId,
    required this.tenant,
    required this.deliveries,
  });

  double? _distanceInKm() {
    double total = 0;
    var found = false;
    for (final delivery in deliveries) {
      final raw = delivery['distanciaKm'] ??
          delivery['distanciaTotalKm'] ??
          delivery['distanceKm'];
      if (raw is num && raw.isFinite && raw >= 0) {
        total += raw.toDouble();
        found = true;
      }
    }
    return found ? total : null;
  }

  @override
  Widget build(BuildContext context) {
    final distance = _distanceInKm();
    final value = distance == null
        ? '—'
        : '${distance.toStringAsFixed(distance >= 100 ? 0 : 1)} km';

    return Semantics(
      label: distance == null
          ? 'Distância da jornada ainda não calculada'
          : 'Distância da jornada, $value',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.statusBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.route_rounded, color: AppTheme.statusBlue),
              ),
              const Spacer(),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Distância',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
