import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/epsg3395.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:infra/misc/geolocator.dart';
import 'package:infra/widgets.dart';
import 'package:latlong2/latlong.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapController? mapController = MapController();
  double currentZoom = 17.5;
  LatLng currentCenter = LatLng(45.200051263299, 33.357208643387);
  int showRadius = 200;
  //List<Map<String, dynamic>> ponBoxes = [];
  int selectedPorts = 0, usedPorts = 0;

  @override
  Widget build(BuildContext context) {
    //print(ponBoxes);
    return Scaffold(
      appBar: AppBar(
        title: Text('Инфраструктура PON'),
        actions: [
          IconButton(
            onPressed: () async {
              var pos = await determinePosition();
              print(pos.toJson());
              //print(LatLng.fromJson(pos.toJson()));
              print(mapController?.move(LatLng(pos.latitude, pos.longitude), currentZoom));
            },
            icon: Icon(Icons.location_searching)),
          IconButton(
            onPressed: () async {
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
                            Text('Широта: ${currentCenter.latitude}'),
                            Text('Долгота: ${currentCenter.longitude}'),
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
                                  'long': currentCenter.longitude,
                                  'lat': currentCenter.latitude,
                                  'ports': selectedPorts,
                                  'used_ports': usedPorts,
                                  'added_by': activeUser['login']
                                };
                                var res = await sb.insert(box).select();
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
            },
            icon: Icon(Icons.add_box)),
        ],
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
                //print(position);
                currentCenter = position.center!;
                updates();
              },
              onMapEvent: (event) {
                currentZoom = event.zoom;
              },
            ),
            children: [
              yandexMapTileLayer,
              //openStreetMapTileLayer,
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
                              return ponBoxWidget(ponBox, currentZoom);
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
