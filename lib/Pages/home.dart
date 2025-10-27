import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/epsg3395.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:latlong2/latlong.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapController? mapController;
  double currentZoom = 18.0;
  //List<Map<String, dynamic>> ponBoxes = [];
  bool addingMode = false;
  int selectedPorts = 0, usedPorts = 0;

  @override
  Widget build(BuildContext context) {
    //print(ponBoxes);
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
              crs: const Epsg3395(),
              center: LatLng(45.200051263299, 33.357208643387),
              zoom: currentZoom,
              maxZoom: 18,
              onMapEvent: (event) {
                if (addingMode) {
                  showDialog<Map<String, dynamic>>(
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
                                Text('Широта: ${event.center.latitude}'),
                                Text('Долгота: ${event.center.longitude}'),
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
                                    var box = {
                                      'long': event.center.longitude,
                                      'lat': event.center.latitude,
                                      'ports': selectedPorts,
                                      'used_ports': usedPorts,
                                      'added_by': activeUser['login']
                                    };
                                    var res = await sb.insert(box).select();
                                    addingMode = false;
                                    selectedPorts = 0;
                                    usedPorts = 0;
                                    // ignore: use_build_context_synchronously
                                    Navigator.of(context).pop(res.first);
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
                    setState(() {
                      if (onValue != null && onValue.isNotEmpty) {
                        ponBoxes.add(onValue);
                      }
                    });
                  });
                }
              },
            ),
            children: [
              yandexMapTileLayer,
              //openStreetMapTileLayer,
              MarkerLayer(
                markers:
                    ponBoxes
                        .map(
                          (ponBox) => Marker(
                            height: currentZoom * 1.5,
                            width: currentZoom * 1.6,
                            point: LatLng(ponBox['lat'], ponBox['long']),
                            builder: (context) {
                              return Stack(
                                children: [
                                  Positioned(
                                    top: -3,
                                    child: Container(
                                      height: currentZoom,
                                      decoration: BoxDecoration(
                                        color: Colors.yellow,
                                        //border: BoxBorder.all(),
                                        //borderRadius: BorderRadius.all(Radius.zero),
                                      ),
                                      child: Text(
                                        textAlign: TextAlign.center,
                                        '${ponBox['ports']}',
                                        style: TextStyle(fontSize: currentZoom * 1),
                                      ),
                                    ),
                                  ),
                                  Positioned(right: 15, top: -10, child: Text(ponBox['used_ports'].toString()))
                                ]
                              );
                            }
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
