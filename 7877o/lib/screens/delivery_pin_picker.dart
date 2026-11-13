import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// A general service-area starting point, not the customer's location.
const kampalaMapCenter = LatLng(0.3476, 32.5825);

// The checkout RPC accepts at most eight decimal places. Normalize once so the
// displayed, saved and retried coordinates are identical.
LatLng normalizeDeliveryPin(LatLng pin) => LatLng(
  double.parse(pin.latitude.toStringAsFixed(8)),
  double.parse((((pin.longitude + 180) % 360) - 180).toStringAsFixed(8)),
);

String pinCoordinates(LatLng pin) =>
    '${pin.latitude.toStringAsFixed(8)}, ${pin.longitude.toStringAsFixed(8)}';

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;
}

/// Called only after the customer presses the location button. One fix, no stream.
Future<LatLng> deliveryCurrentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailable('Location is off. Turn it on or choose a pin on the map.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationUnavailable('Location permission is blocked. Change it in settings or choose a pin on the map.');
  }
  if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
    throw const LocationUnavailable('Location permission was not granted. Choose a pin on the map instead.');
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    ),
  );
  return LatLng(position.latitude, position.longitude);
}

/// The injectable callbacks let widget tests exercise the picker without GPS or network.
class DeliveryPinPicker extends StatefulWidget {
  const DeliveryPinPicker({super.key, this.initialPin, this.locate, this.mapBuilder});

  final LatLng? initialPin;
  final Future<LatLng> Function()? locate;
  final Widget Function(ValueChanged<LatLng> onTap, LatLng? selected)? mapBuilder;

  @override
  State<DeliveryPinPicker> createState() => _DeliveryPinPickerState();
}

class _DeliveryPinPickerState extends State<DeliveryPinPicker> {
  final mapController = MapController();
  LatLng? pin;
  bool locating = false;
  bool tilesFailed = false;
  String? locationError;

  @override
  void initState() {
    super.initState();
    pin = widget.initialPin;
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  void selectPin(LatLng value) {
    if (locating) return;
    setState(() { pin = normalizeDeliveryPin(value); locationError = null; });
  }

  Future<void> useCurrentLocation() async {
    setState(() { locating = true; locationError = null; });
    try {
      final location = normalizeDeliveryPin(await (widget.locate ?? deliveryCurrentLocation)());
      if (!mounted) return;
      setState(() => pin = location);
      if (widget.mapBuilder == null) mapController.move(location, 16);
    } on LocationUnavailable catch (error) {
      if (mounted) setState(() => locationError = error.message);
    } catch (_) {
      if (mounted) setState(() => locationError = 'Could not get your location. Choose a pin on the map or continue without one.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Widget buildMap() {
    if (widget.mapBuilder != null) return widget.mapBuilder!(selectPin, pin);
    return Stack(children: [
      FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: pin ?? kampalaMapCenter,
          initialZoom: pin == null ? 12 : 16,
          maxZoom: 19,
          onTap: (_, point) => selectPin(point),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.graphen.graphenbags',
            maxNativeZoom: 19,
            panBuffer: 0,
            errorTileCallback: (_, __, ___) {
              if (!tilesFailed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !tilesFailed) setState(() => tilesFailed = true);
                });
              }
            },
          ),
          MarkerLayer(markers: [
            if (pin != null) Marker(
              point: pin!, width: 40, height: 40, alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on, size: 40, color: Colors.red),
            ),
          ]),
        ],
      ),
      Positioned(right: 0, bottom: 0, child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 11, color: Colors.black)),
          ),
        ),
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose delivery pin')),
    body: SafeArea(child: Column(children: [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Tap the map to place or move your pin. The starting view is Kampala, not your location.'),
      ),
      Expanded(child: buildMap()),
      if (tilesFailed) const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text('Some map tiles could not load. Check your connection, or go back and use your address without a pin.'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(pin == null ? 'No pin selected' : 'Selected: ${pinCoordinates(pin!)}'),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('If saved, these coordinates will be shared with Graphens for delivery. A written address is still required.'),
      ),
      if (locationError != null) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(locationError!, style: const TextStyle(color: Colors.red)),
      ),
      Wrap(alignment: WrapAlignment.center, children: [
        TextButton.icon(
          onPressed: locating ? null : useCurrentLocation,
          icon: const Icon(Icons.my_location),
          label: Text(locating ? 'Finding location…' : 'Use current location'),
        ),
        TextButton(onPressed: locating || pin == null ? null : () => setState(() => pin = null), child: const Text('Clear pin')),
        ElevatedButton(onPressed: locating || pin == null ? null : () => Navigator.pop(context, pin), child: const Text('Save pin')),
      ]),
    ])),
  );
}
