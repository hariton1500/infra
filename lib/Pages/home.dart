import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapController? mapController;
  var sb = Supabase.instance.client.from('PON_boxes');
  double currentZoom = 12.0;
  List<Map<String, dynamic>> ponBoxes = [];
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    sb.select().then((onValue) {
      ponBoxes = onValue;
      print(ponBoxes);
      updates();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Инфраструктура PON')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              //crs: CrsSimple(),
              initialCenter: LatLng(45.200051263299, 33.357208643387),
              initialZoom: 12,
              onMapEvent: (event) {
                //print(event.camera.zoom);
                setState(() {});
              },
            ),
            children: [
              //yandexMapTileLayer,
              openStreetMapTileLayer,
              MarkerLayer(
                markers:
                    ponBoxes
                        .map(
                          (ponBox) => Marker(
                            height: currentZoom * 1.6,
                            point: LatLng(ponBox['lat'], ponBox['long']),
                            child: Container(
                              height: currentZoom,
                              decoration: BoxDecoration(
                                color: Colors.yellow,
                                border: BoxBorder.all(),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${ponBox['used_ports']}/${ponBox['ports']}',
                                style: TextStyle(fontSize: currentZoom),
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void updates() {
    setState(() {});
  }
}
