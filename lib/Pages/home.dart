import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
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
  bool addingMode = false;
  int selectedPorts = 0, usedPorts = 0;
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            addingMode = true;
          });
        },
        child: Icon(Icons.add),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              //crs: CrsSimple(),
              initialCenter: LatLng(45.200051263299, 33.357208643387),
              initialZoom: 12,
              onMapEvent: (event) {
                if (addingMode) {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        child: StatefulBuilder(
                          builder: (BuildContext context, void Function(void Function()) setState) { 
                            return SizedBox(
                            width: 300,
                            height: 300,
                            child: Column(
                              children: [
                                Text('Широта: ${event.camera.center.latitude}'),
                                Text('Долгота: ${event.camera.center.longitude}'),
                                Card(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Text('Количество портов:'),
                                    ...[2, 4, 8, 16].map((q) => InkWell(
                                      child: q == selectedPorts ? Text('[>$q<]') : Text('[  $q  ]'),
                                      onTap: () {
                                        setState(() {
                                          selectedPorts = q;
                                        },);
                                      },
                                    )
                                  ),
                                  ])
                                ),
                                Card(
                                  child: Wrap(
                                    spacing: 5,
                                    runSpacing: 5,
                                    children: [
                                      Text('Занятых портов:'),
                                      ...List<int>.generate(selectedPorts + 1, (i) => i).map((q) => InkWell(
                                        child: q == usedPorts ? Text('[>$q<]') : Text('[  $q  ]'),
                                        onTap: () {
                                          setState(() {
                                            usedPorts = q;
                                          },);
                                        },
                                      )),
                                    ]
                                  )
                                ),
                                if (selectedPorts > 0) ElevatedButton(
                                  onPressed: () async {
                                    var res = await sb.insert({
                                      'long': event.camera.center.longitude,
                                      'lat': event.camera.center.latitude,
                                      'ports': selectedPorts,
                                      'used_ports': usedPorts,
                                      'added_by': activeUser['login']
                                    }).select();
                                    addingMode = false;
                                    selectedPorts = 0;
                                    usedPorts = 0;
                                    Navigator.of(context).pop(res);
                                  },
                                  child: Text('Добавить')
                                )
                              ],
                            ),
                          );
                           },
                        ),
                      );
                    }
                  ).then((onValue) {
                    sb.select().then((onValue) {
                      ponBoxes = onValue;
                      print(ponBoxes);
                      updates();
                    });
                  });
                }
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
                            width: currentZoom * 1,
                            point: LatLng(ponBox['lat'], ponBox['long']),
                            child: Container(
                              height: currentZoom,
                              decoration: BoxDecoration(
                                color: Colors.yellow,
                                //border: BoxBorder.all(),
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
