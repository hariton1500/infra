import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/epsg3395.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:infra/misc/geolocator.dart';
import 'package:infra/models.dart';
import 'package:infra/widgets.dart';
import 'package:infra/Pages/ponboxshow.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:flutter_map_line_editor/flutter_map_line_editor.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController mapController = MapController();
  double currentZoom = 17.5;
  LatLng currentCenter = const LatLng(45.200051263299, 33.357208643387);
  int showRadius = 200;
  int selectedPorts = 0;
  int usedPorts = 0;
  bool isSatLayer = false;
  bool hasDivider = false;
  int? dividerPorts;
  String mode = '';
  Cable addingCable = Cable(points: []);
  List<LatLng> addingCablePoints = [];
  Map<String, dynamic>? selectedPillar;
  PolyEditor? polyEditor;

  @override
  void initState() {
    polyEditor = PolyEditor(
      points: addingCable.points!,
      pointIcon: Icon(Icons.crop_square, size: 23),
      intermediateIcon: Icon(Icons.lens, size: 15, color: Colors.grey),
      callbackRefresh: () => {setState(() {})},
    );
    super.initState();
    _initializeFromParams();
  }

  void _initializeFromParams() {
    if (params.containsKey('order') &&
        params.containsKey('lat') &&
        params.containsKey('long')) {
      try {
        final lat = double.parse(params['lat']!);
        final lng = double.parse(params['long']!);
        setState(() {
          currentCenter = LatLng(lat, lng);
        });
      } catch (e) {
        debugPrint('Ошибка парсинга координат: $e');
      }
    }

    if (params.containsKey('getpoint')) {
      setState(() {
        mode = 'getpoint';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инфраструктура PON'),
        actions: [
          _buildLocationButton(),
          _buildRadiusButton(),
          _buildAddMenu(),
          _buildLayerToggle(),
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
                if (position.center != null) {
                  currentCenter = position.center!;
                  setState(() {});
                }
              },
              onTap: (tapPosition, point) {
                if (mode.startsWith('addingcable')) {
                  _handleTapForAddingCable(point);
                }
              },
            ),
            children: [
              if (isSatLayer) yandexMapSatTileLayer else yandexMapTileLayer,
              if (!mode.startsWith('addingcable')) _buildRadiusCircleLayer(),
              if (!mode.startsWith('addingcable')) _buildCenterMarker(),
              if (mode != 'changePillar') _buildPonBoxMarkers(),
              _buildPillarMarkers(),
              ..._buildCables(),
              if (mode == 'changePillar') _buildLineFromOldPillarToCenter(),
              if (mode.startsWith('addingcable')) ..._buildAddingCable(),
            ],
          ),
          if (mode == 'changePillar') _buildPillarEditModeOverlay(),
          if (mode.startsWith('addingcable')) _buildCableEditModeOverlay(),
          if (mode == 'changePillar') _buildPillarActions(),
          if (mode.startsWith('addingcable')) _buildAddingCableActions(),
          if (mode == 'getpoint') _buildGetPointModeOverlay(),
        ],
      ),
    );
  }

  Widget _buildLocationButton() {
    return IconButton(
      onPressed: () async {
        try {
          final pos = await determinePosition();
          mapController.move(LatLng(pos.latitude, pos.longitude), currentZoom);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Не удалось определить местоположение: $e'),
              ),
            );
          }
        }
      },
      icon: const Icon(Icons.location_searching),
    );
  }

  Widget _buildRadiusButton() {
    return IconButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Радиус отображения'),
              content: StatefulBuilder(
                builder:
                    (context, setStateDialog) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Радиус: $showRadius м'),
                        Slider(
                          value: showRadius.toDouble(),
                          min: 50,
                          max: 3000,
                          divisions: 59,
                          label: '$showRadius',
                          onChanged: (v) {
                            setStateDialog(() => showRadius = v.round());
                            setState(() {});
                          },
                        ),
                      ],
                    ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            );
          },
        );
      },
      icon: const Icon(Icons.radar),
    );
  }

  Widget _buildAddMenu() {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'ponbox':
            _showAddPonBoxDialog();
            break;
          case 'opora':
            _addOpora();
            break;
          case 'cable':
            _addCable();
            break;
        }
      },
      icon: const Icon(Icons.add),
      itemBuilder:
          (context) => [
            const PopupMenuItem(value: 'ponbox', child: Text('PON box')),
            const PopupMenuItem(value: 'opora', child: Text('Опора')),
            const PopupMenuItem(value: 'cable', child: Text('Кабель')),
          ],
    );
  }

  Widget _buildLayerToggle() {
    return IconButton(
      onPressed: () => setState(() => isSatLayer = !isSatLayer),
      icon: Icon(isSatLayer ? Icons.layers : Icons.layers_outlined),
    );
  }

  Widget _buildRadiusCircleLayer() {
    return CircleLayer(
      circles: [
        CircleMarker(
          point: currentCenter,
          radius: showRadius.toDouble(),
          useRadiusInMeter: true,
          color: Colors.white10,
          borderStrokeWidth: 1,
          borderColor: Colors.black38,
        ),
      ],
    );
  }

  Widget _buildCenterMarker() {
    return CircleLayer(
      circles: [
        if (mode != 'changePillar')
          CircleMarker(
            point: currentCenter,
            radius: 1,
            useRadiusInMeter: true,
            color: Colors.white,
            borderStrokeWidth: 1,
            borderColor: Colors.black,
          )
        else
          CircleMarker(
            point: currentCenter,
            radius: 3,
            useRadiusInMeter: true,
            color: Colors.green,
            borderStrokeWidth: 1,
            borderColor: Colors.black,
          ),
      ],
    );
  }

  Widget _buildPonBoxMarkers() {
    final distance = Distance();
    return MarkerLayer(
      markers:
          ponBoxes
              .where(
                (box) =>
                    distance(LatLng(box['lat'], box['long']), currentCenter) <=
                    showRadius,
              )
              .map(
                (ponBox) => Marker(
                  width: currentZoom * 1.5,
                  height: currentZoom * 1.6,
                  point: LatLng(ponBox['lat'], ponBox['long']),
                  builder:
                      (context) => GestureDetector(
                        child: ponBoxWidget(ponBox, currentZoom),
                        onTap:
                            () => showPonBoxInfoSheet(
                              context,
                              ponBox,
                              () => setState(() {}),
                              currentMapCenter: currentCenter,
                            ),
                      ),
                ),
              )
              .toList(),
    );
  }

  Widget _buildPillarMarkers() {
    return MarkerLayer(
      markers:
          pillars.map((pillar) {
            return Marker(
              width: currentZoom / 3,
              height: currentZoom / 3,
              point: LatLng(pillar['lat'], pillar['long']),
              builder:
                  (context) => GestureDetector(
                    onLongPress: () {
                      setState(() {
                        mode = 'changePillar';
                        selectedPillar = pillar;
                        mapController.move(
                          LatLng(pillar['lat'], pillar['long']),
                          currentZoom,
                        );
                      });
                    },
                    child: Pillar.fromMap(pillar).pillarWidget(currentZoom),
                  ),
            );
          }).toList(),
    );
  }

  Widget _buildLineFromOldPillarToCenter() {
    return PolylineLayer(
      polylineCulling: true,
      polylines: [
        Polyline(
          points: [
            LatLng(selectedPillar!['lat'], selectedPillar!['long']),
            currentCenter,
          ],
        ),
      ],
    );
  }

  Widget _buildPillarEditModeOverlay() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.yellow.withAlpha(200),
        child: const Text(
          'Режим перемещения опоры.\nПереместите центр карты и нажмите "Сохранить"',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  List<Widget> _buildCables() {
    //print('building cables:\n$cables');
    var showCables =
        cables
            .where(
              (c) => c.isInRadius(toPoint: currentCenter, radius: showRadius),
            )
            .toList();
    //print('filtered ${showCables.length}');
    return [
      PolylineLayer(
        polylines:
            showCables
                .map(
                  (cable) => Polyline(
                    points: cable.points!,
                    strokeWidth: cable.fibersNumber! / 12,
                    //useStrokeWidthInMeter: true,
                  ),
                )
                .toList(),
      ),
      ...showCables.map(
        (cable) => MarkerLayer(
          markers:
              cable.points!
                  .map(
                    (point) => Marker(
                      point: point,
                      builder:
                          (context) => GestureDetector(
                            child: Icon(Icons.crop_square_rounded, size: 5),
                            onLongPress: () {
                              setState(() {
                                mode = 'addingcableandchange';
                                addingCable = cable;
                                polyEditor = PolyEditor(
                                  points: addingCable.points!,
                                  pointIcon: Icon(Icons.crop_square, size: 23),
                                  intermediateIcon: Icon(Icons.lens, size: 15, color: Colors.grey),
                                  callbackRefresh: () => {setState(() {})},
                                );
                              });
                            },
                          ),
                    ),
                  )
                  .toList(),
        ),
      ),
    ];
  }

  List<Widget> _buildAddingCable() {
    //print('build cable $addingCable');
    return [
      PolylineLayer(polylines: [Polyline(points: addingCablePoints)]),
      DragMarkers(markers: polyEditor!.edit()),
    ];
  }

  Widget _buildAddingCableActions() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                int? fibersNumber = addingCable.fibersNumber;
                int? dialogRes = await showModalBottomSheet<int>(
                  context: context,
                  builder:
                      (context) => Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          spacing: 10,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Укажите количество волокон в кабеле:'),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runSpacing: 10,
                              spacing: 10,
                              children: [
                                ...[
                                  1,
                                  2,
                                  4,
                                  8,
                                  12,
                                  16,
                                  20,
                                  24,
                                  32,
                                  36,
                                  48,
                                  64,
                                  96,
                                ].map(
                                  (i) => ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context, i);
                                    },
                                    child: addingCable.fibersNumber != null && addingCable.fibersNumber == i ? Text(i.toString(), style: TextStyle(fontWeight: FontWeight.bold),) : Text(i.toString()),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                );
                if (dialogRes != null) fibersNumber = dialogRes;
                if (fibersNumber == null) return;
                //save addingCablePoints to DB
                print('save cable:\n $addingCable');
                addingCable.fibersNumber = fibersNumber;
                var res = await addingCable.storeCable(mode == 'addingcablenew' ? null : addingCable);
                print('[DB]:\n$res');
                if (res.isNotEmpty) {
                  setState(() {
                    addingCable.id = res.first['id'];
                    cables.add(addingCable);
                    mode = '';
                  });
                } else {
                  reportError('Ошибка сохранения кабеля');
                }
              },
              label: Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }

  _handleTapForAddingCable(LatLng pos) {
    polyEditor!.add(addingCable.points!, pos);
  }

  Widget _buildCableEditModeOverlay() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.yellow.withValues(alpha: 0.8),
        child: const Text(
          'Режим внесения кабеля.\nДобавляйте точки крепления кабеля',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPillarActions() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () async {
              var historyData = {
                'pillar_id': selectedPillar?['id'],
                'by_name': activeUser['login'],
                'before': selectedPillar,
              };
              var pillar = Pillar(
                id: selectedPillar?['id'],
                lat: selectedPillar?['lat'],
                long: selectedPillar?['long'],
              );
              var res = await pillar.updatePillarPoint(newPoint: currentCenter);
              if (res.isNotEmpty) {
                setState(() {
                  mode = '';
                  selectedPillar?['lat'] = currentCenter.latitude;
                  selectedPillar?['long'] = currentCenter.longitude;
                });
                historyData['after'] = selectedPillar;
                sbHistory.insert(historyData).then(print);
              }
            },
            label: Text('Сохранить'),
            icon: Icon(Icons.save),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Pillar(id: selectedPillar?['id']).markAsDeleted().then((onValue) {
                if (onValue.isNotEmpty) {
                  setState(() {
                    mode = '';
                    pillars.remove(selectedPillar);
                    selectedPillar = null;
                  });
                } else {
                  reportError('Не удалось удалить опору');
                }
              });
            },
            label: Text('Удалить'),
          ),
          //add delete button
        ],
      ),
    );
  }

  Widget _buildGetPointModeOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: () {
            final global = globalContext;
            final opener = global.getProperty('opener'.toJS);
            if (opener != null && !opener.isUndefined && !opener.isNull) {
              final openerObj = opener as JSObject;
              openerObj.callMethod(
                (params.containsKey('callback')
                        ? params['callback']
                        : 'returnGPScoodrs')
                    .toString()
                    .toJS,
                '${currentCenter.latitude} ${currentCenter.longitude}'.toJS,
              );
            }
            setState(() {
              mode = '';
            });
          },
          icon: const Icon(Icons.place),
          label: const Text('Сохранить координаты'),
        ),
      ),
    );
  }

  Future<void> _showAddPonBoxDialog() async {
    int localPorts = selectedPorts;
    int localUsed = usedPorts;
    bool localHasDivider = hasDivider;
    int? localDividerPorts = dividerPorts;

    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        bool canAdd = localPorts > 0 && localUsed <= localPorts;
        return AlertDialog(
          title: const Text('Добавить PON бокс'),
          scrollable: true,
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Координаты: ${currentCenter.latitude.toStringAsFixed(6)}, ${currentCenter.longitude.toStringAsFixed(6)}',
                    ),
                    const SizedBox(height: 16),
                    const Text('Количество портов'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final q in [2, 4, 8, 16])
                          ChoiceChip(
                            label: Text(q.toString()),
                            selected: localPorts == q,
                            onSelected: (_) {
                              setStateDialog(() {
                                localPorts = q;
                                if (localUsed > localPorts) {
                                  localUsed = localPorts;
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Занятых портов'),
                    Slider(
                      value: localUsed.toDouble().clamp(
                        0,
                        localPorts.toDouble(),
                      ),
                      min: 0,
                      max: localPorts > 0 ? localPorts.toDouble() : 16,
                      divisions: localPorts > 0 ? localPorts : 16,
                      label: '$localUsed',
                      onChanged: (v) {
                        setStateDialog(() {
                          localUsed = v.round();
                        });
                      },
                    ),
                    Text(
                      'Занято: $localUsed из $localPorts',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (localUsed > localPorts)
                      Text(
                        'Слишком много',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Первичный делитель'),
                      subtitle:
                          localHasDivider && localDividerPorts != null
                              ? Text('На $localDividerPorts портов')
                              : null,
                      value: localHasDivider,
                      onChanged: (value) {
                        setStateDialog(() {
                          localHasDivider = value;
                          if (!value) localDividerPorts = null;
                        });
                      },
                    ),
                    if (localHasDivider) ...[
                      const Text('Портов делителя'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final q in [2, 4, 8, 16])
                            ChoiceChip(
                              label: Text(q.toString()),
                              selected: localDividerPorts == q,
                              onSelected: (_) {
                                setStateDialog(() {
                                  localDividerPorts =
                                      localDividerPorts == q ? null : q;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton.icon(
              onPressed:
                  canAdd
                      ? () async {
                        final box = {
                          'long': currentCenter.longitude,
                          'lat': currentCenter.latitude,
                          'ports': localPorts,
                          'used_ports': localUsed,
                          'added_by': activeUser['login'],
                        };
                        if (localHasDivider && localDividerPorts != null) {
                          box['has_divider'] = true;
                          box['divider_ports'] = localDividerPorts;
                        }
                        final res = await sb.insert(box).select();
                        if (res.isNotEmpty) {
                          Navigator.of(context).pop(res.first);
                        }
                      }
                      : null,
              icon: const Icon(Icons.check),
              label: const Text('Добавить'),
            ),
          ],
        );
      },
    ).then((value) {
      if (value != null) {
        ponBoxes.add(value);
      }
    });
  }

  Future<void> _addOpora() async {
    final pillar = {
      'long': currentCenter.longitude,
      'lat': currentCenter.latitude,
      'added_by': activeUser['login'],
    };
    final res = await sbPillars.insert(pillar).select();
    if (res.isNotEmpty && mounted) {
      setState(() {
        pillars.add(pillar);
      });
    }
  }

  Future<void> _addCable() async {
    setState(() {
      addingCable = Cable(points: []);
      mode = 'addingcablenew';
    });
  }

  void reportError(String s) {
    //show error message by scaffoldMessenger
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
}
