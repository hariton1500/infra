import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/epsg3395.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapController? mapController;
  double currentZoom = 18.0;
  LatLng currentCenter = LatLng(45.200051263299, 33.357208643387);
  int showRadius = 200;
  //List<Map<String, dynamic>> ponBoxes = [];
  bool addingMode = false;
  int selectedPorts = 0, usedPorts = 0;
  FollowOnLocationUpdate _alignPositionOnUpdate = FollowOnLocationUpdate.once;
  final StreamController<double?> _alignPositionStreamController = StreamController<double?>();

  @override
  void dispose() {
    _alignPositionStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //print(ponBoxes);
    return Scaffold(
      appBar: AppBar(
        title: Text('Инфраструктура PON'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _alignPositionOnUpdate = FollowOnLocationUpdate.once;
              });
            },
            icon: Icon(Icons.location_searching))
        ],
        ),
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
              center: currentCenter,
              zoom: currentZoom,
              maxZoom: 18,
              onPositionChanged: (position, hasGesture) {
                print(position);
              },
              onMapEvent: (event) {
                setState(() {
                  currentCenter = event.center;
                });
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
              CurrentLocationLayer(
                followOnLocationUpdate: _alignPositionOnUpdate,
                
                //followCurrentLocationStream: _alignPositionStreamController,
              ),
              MarkerLayer(
                markers:
                    ponBoxes.where((box) {
                        var dist = DistanceVincenty();
                        return dist(LatLng(box['lat'], box['long']), currentCenter) <= showRadius;
                      }).map(
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
                                      ),
                                      child: Text(
                                        textAlign: TextAlign.center,
                                        '${ponBox['ports']}',
                                        style: TextStyle(fontSize: currentZoom * 0.8),
                                      ),
                                    ),
                                  ),
                                  //Positioned(right: 15, top: -10, child: Text(ponBox['used_ports'].toString()))
                                ]
                              );
                            }
                          ),
                        )
                        .toList(),
              ),
              CircleLayer(
                circles: [
                  CircleMarker(point: currentCenter, radius: showRadius.toDouble(), useRadiusInMeter: true, color: Colors.white10, borderStrokeWidth: 1, borderColor: Colors.black38),
                  CircleMarker(point: currentCenter, radius: 1, useRadiusInMeter: true, color: Colors.white, borderStrokeWidth: 1, borderColor: Colors.black)
                ]
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
