
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
  int selectedPorts = 0, usedPorts = 0;
  bool isSatLayer = false;

  String _formatDateDMY(dynamic value) {
    try {
      DateTime dt;
      if (value is DateTime) {
        dt = value.toLocal();
      } else {
        dt = DateTime.parse(value.toString()).toLocal();
      }
      String two(int n) => n < 10 ? '0$n' : '$n';
      return '${two(dt.day)}.${two(dt.month)}.${dt.year}';
    } catch (_) {
      return value?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    //print(ponBoxes);
    return Scaffold(
      appBar: AppBar(
        title: Text('Инфраструктура PON'),
        actions: [
          IconButton(
            onPressed: () async {
              try {
                var pos = await determinePosition();
                print(pos.toJson());
                //print(LatLng.fromJson(pos.toJson()));
                print(mapController?.move(LatLng(pos.latitude, pos.longitude), currentZoom));
              } catch (e) {
                var message = e.toString();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Не удалось определить местоположение: $message')),
                  );
                }
              }
            },
            icon: Icon(Icons.location_searching)),
          IconButton(
            onPressed: () async {
              showDialog<void>(
                context: context,
                builder: (context) {
                  return Dialog(
                    child: StatefulBuilder(
                      builder: (BuildContext context, void Function(void Function()) setStateDialog) {
                        return SizedBox(
                          width: 320,
                          height: 180,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Радиус отображения: $showRadius м'),
                                const SizedBox(height: 8),
                                Slider(
                                  value: showRadius.toDouble(),
                                  min: 50,
                                  max: 3000,
                                  divisions: 59,
                                  label: '$showRadius м',
                                  onChanged: (v) {
                                    setStateDialog(() {});
                                    setState(() { showRadius = v.round(); });
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('Закрыть'),
                                  ),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }
              );
            },
            icon: Icon(Icons.radar)
          ),
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
            icon: Icon(Icons.add_box)
          ),
          IconButton(
            onPressed: () => setState(() {
              isSatLayer = !isSatLayer;
            }),
            icon: Icon(Icons.layers)
          ),
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
              /*
              onMapEvent: (event) {
                currentZoom = event.zoom;
                print('onEvent');
                print(event.source.index);
              },*/
            ),
            children: [
              isSatLayer ? yandexMapSatTileLayer : yandexMapTileLayer,
              //openStreetMapTileLayer,
              CircleLayer(
                circles: [
                  CircleMarker(point: currentCenter, radius: showRadius.toDouble(), useRadiusInMeter: true, color: Colors.white10, borderStrokeWidth: 1, borderColor: Colors.black38),
                  CircleMarker(point: currentCenter, radius: 1, useRadiusInMeter: true, color: Colors.white, borderStrokeWidth: 1, borderColor: Colors.black)
                ]
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
                              return GestureDetector(
                                child: ponBoxWidget(ponBox, currentZoom),
                                onTap: () {
                                  print('onTap');
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (context) {
                                      return SafeArea(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Center(
                                                child: Container(
                                                  width: 36,
                                                  height: 4,
                                                  decoration: BoxDecoration(
                                                    color: Colors.black26,
                                                    borderRadius: BorderRadius.circular(2),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  Icon(Icons.developer_board, color: Theme.of(context).colorScheme.primary),
                                                  const SizedBox(width: 8),
                                                  Text('PON Box #${ponBox['id']}', style: Theme.of(context).textTheme.titleMedium),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  Chip(
                                                    avatar: const Icon(Icons.settings_ethernet, size: 18),
                                                    label: Text('Портов: ${ponBox['ports']}'),
                                                  ),
                                                  Chip(
                                                    avatar: const Icon(Icons.check_circle, size: 18),
                                                    label: Text('Занято: ${ponBox['used_ports']}'),
                                                  ),
                                                  Chip(
                                                    avatar: const Icon(Icons.location_on, size: 18),
                                                    label: Text('${ponBox['lat']}, ${ponBox['long']}'),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              ListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                leading: const Icon(Icons.person_outline),
                                                title: Text(ponBox['added_by'] != null ? 'Добавлен: ${ponBox['added_by']}' : 'Добавивший не указан'),
                                              ),
                                              ListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                leading: const Icon(Icons.event_note),
                                                title: Text('Создан: ${_formatDateDMY(ponBox['created_at'])}'),
                                              ),
                                              const SizedBox(height: 8),
                                              if (params.containsKey('getponbox')) Align(
                                                alignment: Alignment.centerRight,
                                                child: ElevatedButton.icon(
                                                  onPressed: () {
                                                    print('Выбран пон бокс ${ponBox['id']}');
                                                    //Navigator.of(context).pop(ponBox['id']);
                                                  },
                                                  icon: const Icon(Icons.check),
                                                  label: const Text('Выбрать этот'),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                  );
                                },
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
