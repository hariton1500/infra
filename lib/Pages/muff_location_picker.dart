import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/misc/geolocator.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:latlong2/latlong.dart';

class MuffLocationPickerPage extends StatefulWidget {
  const MuffLocationPickerPage({
    super.key,
    this.initial,
  });

  final LatLng? initial;

  @override
  State<MuffLocationPickerPage> createState() => _MuffLocationPickerPageState();
}

class _MuffLocationPickerPageState extends State<MuffLocationPickerPage> {
  final MapController _mapController = MapController();
  LatLng? _selected;
  double _zoom = 17;
  bool _sat = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? const LatLng(55.751244, 37.618423);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор геопозиции'),
        actions: [
          IconButton(
            onPressed: () async {
              try {
                final pos = await determinePosition();
                final here = LatLng(pos.latitude, pos.longitude);
                _mapController.move(here, _zoom);
                setState(() => _selected = here);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Не удалось определить позицию: $e')),
                );
              }
            },
            icon: const Icon(Icons.my_location),
            tooltip: 'Текущее местоположение',
          ),
          IconButton(
            onPressed: () => setState(() => _sat = !_sat),
            icon: Icon(_sat ? Icons.layers : Icons.layers_outlined),
            tooltip: 'Слой',
          ),
          IconButton(
            onPressed:
                _selected == null
                    ? null
                    : () => Navigator.of(context).pop(_selected),
            icon: const Icon(Icons.check),
            tooltip: 'Сохранить',
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: center,
          zoom: _zoom,
          maxZoom: 19,
          onTap: (_, point) => setState(() => _selected = point),
          onPositionChanged: (pos, _) {
            if (pos.zoom != null) _zoom = pos.zoom!;
          },
        ),
        children: [
          _sat ? yandexMapSatTileLayer : yandexMapTileLayer,
          if (_selected != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _selected!,
                  width: 40,
                  height: 40,
                  builder:
                      (context) => const Icon(
                        Icons.place,
                        color: Colors.red,
                        size: 36,
                      ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
