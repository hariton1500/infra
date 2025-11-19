
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/epsg3395.dart';
//import 'package:infra/misc/gecoding.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:infra/misc/geolocator.dart';
import 'package:infra/widgets.dart';
import 'package:infra/Pages/ponboxshow.dart';
import 'package:latlong2/latlong.dart';
import 'package:universal_html/html.dart' as html;

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
  bool hasDivider = false;
  int? dividerPorts;
  String mode = '';

  @override
  void initState() {
    if (params.containsKey('order') && params.containsKey('lat')&& params.containsKey('long')) {
      //getGeoCoding(params['address']!, source: 'osm');
      try {
        setState(() {
          currentCenter = LatLng(double.parse(params['lat']!), double.parse(params['long']!));
        });
      } catch (e) {
        print(e);        
      }
    }
    if (params.containsKey('getpoint')) {
      setState(() {
        mode = 'getpoint';
      });
    }
    super.initState();
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
                        bool canAdd = selectedPorts > 0 && usedPorts <= selectedPorts;
                        return SizedBox(
                          width: 360,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.add_box, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text('Добавить PON бокс', style: Theme.of(context).textTheme.titleMedium),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text('Координаты', style: Theme.of(context).textTheme.labelMedium),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(child: Text('Широта: ${currentCenter.latitude.toStringAsFixed(6)}')),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('Долгота: ${currentCenter.longitude.toStringAsFixed(6)}')),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text('Количество портов', style: Theme.of(context).textTheme.labelMedium),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final q in [2, 4, 8, 16]) ChoiceChip(
                                      label: Text(q.toString()),
                                      selected: selectedPorts == q,
                                      onSelected: (_) {
                                        setState(() {
                                          selectedPorts = q;
                                          if (usedPorts > selectedPorts) usedPorts = selectedPorts;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text('Занятых портов', style: Theme.of(context).textTheme.labelMedium),
                                const SizedBox(height: 6),
                                Slider(
                                  value: usedPorts.toDouble().clamp(0, selectedPorts.toDouble()),
                                  min: 0,
                                  max: (selectedPorts > 0 ? selectedPorts : 16).toDouble(),
                                  divisions: (selectedPorts > 0 ? selectedPorts : 16),
                                  label: '$usedPorts',
                                  onChanged: (v) {
                                    setState(() {
                                      usedPorts = v.round();
                                    });
                                  },
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Выбрано: $usedPorts из $selectedPorts', style: Theme.of(context).textTheme.bodySmall),
                                    if (usedPorts > selectedPorts) Text('Слишком много', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SwitchListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text('Первичный делитель', style: Theme.of(context).textTheme.labelMedium),
                                        subtitle: hasDivider && dividerPorts != null ? Text('На $dividerPorts портов', style: Theme.of(context).textTheme.bodySmall) : null,
                                        value: hasDivider,
                                        onChanged: (value) {
                                          setState(() {
                                            hasDivider = value;
                                            if (!value) dividerPorts = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (hasDivider) ...[
                                  const SizedBox(height: 8),
                                  Text('Портов делителя', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final q in [2, 4, 8, 16]) ChoiceChip(
                                        label: Text(q.toString()),
                                        selected: dividerPorts == q,
                                        onSelected: (_) {
                                          setState(() {
                                            dividerPorts = dividerPorts == q ? null : q;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        hasDivider = false;
                                        dividerPorts = null;
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('Отмена'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: canAdd ? () async {
                                        var box = {
                                          'long': currentCenter.longitude,
                                          'lat': currentCenter.latitude,
                                          'ports': selectedPorts,
                                          'used_ports': usedPorts,
                                          'added_by': activeUser['login']
                                        };
                                        if (hasDivider && dividerPorts != null) {
                                          box['has_divider'] = true;
                                          box['divider_ports'] = dividerPorts;
                                        }
                                        var res = await sb.insert(box).select();
                                        selectedPorts = 0;
                                        usedPorts = 0;
                                        hasDivider = false;
                                        dividerPorts = null;
                                        // ignore: use_build_context_synchronously
                                        Navigator.of(context).pop(res.first);
                                      } : null,
                                      icon: const Icon(Icons.check),
                                      label: const Text('Добавить'),
                                    )
                                  ],
                                )
                              ],
                            ),
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
                                  showPonBoxInfoSheet(
                                    context,
                                    ponBox,
                                    () {
                                      setState(() {});
                                    },
                                    currentMapCenter: currentCenter,
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
          if (mode == 'getpoint') Align(
            alignment: Alignment.topCenter,
            child: Text('Режим указания точки на карте...\nНаведите центр карты на нужную точку и нажмите кнопку\n"Сохранить координаты"', style: TextStyle(color: Colors.red),)
          ),
          if (mode == 'getpoint') Align(
            alignment: Alignment.bottomCenter,
            child: ElevatedButton.icon(onPressed: () {
              //html.window.parent?.postMessage(jsonEncode(currentCenter.toJson()), '*');
              final global = globalContext;
              final opener = global.getProperty('opener'.toJS);
              if (opener != null && !opener.isUndefined && !opener.isNull) {
                final openerObj = opener as JSObject;
                openerObj.callMethod(
                  'returnGPScoodrs'.toJS, 
                  '${currentCenter.latitude} ${currentCenter.longitude}'.toJS
                );
              }
              setState(() {
                mode = '';
              });
            }, label: Text('Сохранить координаты'), icon: Icon(Icons.place),),
          )
        ],
      ),
    );
  }

  void updates() {
    setState(() {});
  }
}
