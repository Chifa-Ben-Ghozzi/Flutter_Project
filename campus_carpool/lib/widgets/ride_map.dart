import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets.dart';

/// Carte OpenStreetMap du trajet : départ (vert), arrivée (rouge) et itinéraire routier.
/// L'itinéraire, la distance et la durée viennent du service gratuit OSRM ;
/// sans réseau, on trace une ligne droite et on estime la distance.
class RideMap extends StatefulWidget {
  final Ride ride;
  const RideMap(this.ride, {super.key});
  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> {
  late final LatLng a = LatLng(widget.ride.fromLat!, widget.ride.fromLng!);
  late final LatLng b = LatLng(widget.ride.toLat!, widget.ride.toLng!);
  List<LatLng>? path; // itinéraire routier
  double? km;
  int? minutes;

  @override
  void initState() {
    super.initState();
    km = const Distance().as(LengthUnit.Meter, a, b) / 1000; // à vol d'oiseau en attendant
    loadRoute();
  }

  Future<void> loadRoute() async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${a.longitude},${a.latitude};${b.longitude},${b.latitude}?overview=full&geometries=geojson');
      final r = await Api.client.get(url).timeout(const Duration(seconds: 8));
      final route = (jsonDecode(r.body)['routes'] as List).first;
      final coords = route['geometry']['coordinates'] as List;
      if (!mounted) return;
      setState(() {
        path = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        km = (route['distance'] as num) / 1000;
        minutes = ((route['duration'] as num) / 60).round();
      });
    } catch (_) {
      // Pas d'itinéraire : on garde la ligne droite
    }
  }

  Widget pin(Color color, IconData icon) => Icon(icon, color: color, size: 36, shadows: const [
        Shadow(blurRadius: 6, color: Colors.black38),
      ]);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        SizedBox(
          height: 220,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds(a, b),
                padding: const EdgeInsets.fromLTRB(40, 50, 40, 30),
                maxZoom: 15,
              ),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.campus_carpool',
                // Mode sombre : on assombrit légèrement les tuiles
                tileBuilder: dark
                    ? (context, tile, _) => ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            0.6, 0, 0, 0, 0, //
                            0, 0.6, 0, 0, 0, //
                            0, 0, 0.6, 0, 0, //
                            0, 0, 0, 1, 0,
                          ]),
                          child: tile,
                        )
                    : null,
              ),
              PolylineLayer(polylines: [
                Polyline(
                  points: path ?? [a, b],
                  strokeWidth: 5,
                  color: scheme.primary,
                  pattern: path == null ? StrokePattern.dashed(segments: const [10, 8]) : const StrokePattern.solid(),
                ),
              ]),
              MarkerLayer(markers: [
                Marker(point: a, width: 40, height: 40, alignment: Alignment.topCenter, child: pin(Colors.green, Icons.trip_origin)),
                Marker(point: b, width: 40, height: 40, alignment: Alignment.topCenter, child: pin(Colors.red, Icons.location_on)),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Icon(Icons.route, color: scheme.primary, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                minutes != null
                    ? context.tr('route_info', {'km': km!.toStringAsFixed(1), 'min': minutes})
                    : context.tr('route_info_approx', {'km': km!.toStringAsFixed(1)}),
              ),
            ),
            TextButton.icon(
              onPressed: () => openUrl(
                context,
                Uri.parse('https://www.google.com/maps/dir/?api=1'
                    '&origin=${a.latitude},${a.longitude}&destination=${b.latitude},${b.longitude}&travelmode=driving'),
              ),
              icon: const Icon(Icons.navigation_outlined, size: 18),
              label: Text(context.tr('navigate')),
            ),
          ]),
        ),
      ]),
    );
  }
}
