import 'dart:async';
import 'dart:convert';
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
  bool isEditingCable = false;
  Map<String, dynamic>? selectedPillar, before;
  late PolyEditor polyEditor;
  TextEditingController commentController = TextEditingController();
  LatLng? _lastAddedPoint;
  int _lastAddedTick = 0;
  Timer? _lastAddedTimer;

  static const int _minCablePoints = 2;

  void _resetPolyEditor() {
    polyEditor = PolyEditor(
      points: addingCable.points!,
      pointIcon: Icon(Icons.crop_square, size: 23),
      intermediateIcon: Icon(Icons.lens, size: 15, color: Colors.grey),
      callbackRefresh: () => {setState(() {})},
    );
  }

  @override
  void dispose() {
    _lastAddedTimer?.cancel();
    commentController.dispose();
    super.dispose();
  }

  void _startEditCable(Cable cable) {
    before = jsonDecode(jsonEncode(cable.toMap()));
    setState(() {
      mode = 'addingcableandchange';
      addingCable = cable;
      isEditingCable = true;
      _resetPolyEditor();
    });
    _fitToCable(cable);
  }

  void _fitToCable(Cable cable) {
    final points = cable.points ?? const <LatLng>[];
    if (points.length < 2) return;
    final bounds = LatLngBounds.fromPoints(points);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      mapController.fitBounds(
        bounds,
        options: const FitBoundsOptions(
          padding: EdgeInsets.all(40),
        ),
      );
    });
  }

  Map<String, dynamic> _cableSnapshot(dynamic source) {
    final map = source is Cable ? source.toMap() : Map<String, dynamic>.from(source as Map);
    return {
      'fibers_number': map['fibers_number'],
      'comment': (map['comment'] ?? '').toString(),
      'points': _pointsSnapshot(map['points']),
    };
  }

  List<List<double>> _pointsSnapshot(dynamic points) {
    if (points == null) return const <List<double>>[];
    if (points is List<LatLng>) {
      return points.map((p) => [p.latitude, p.longitude]).toList();
    }
    if (points is List) {
      final result = <List<double>>[];
      for (final p in points) {
        if (p is LatLng) {
          result.add([p.latitude, p.longitude]);
        } else if (p is List && p.length >= 2) {
          final lat = p[0];
          final lng = p[1];
          if (lat is num && lng is num) {
            result.add([lat.toDouble(), lng.toDouble()]);
          }
        } else if (p is Map) {
          final lat = p['lat'];
          final lng = p['lng'] ?? p['long'];
          if (lat is num && lng is num) {
            result.add([lat.toDouble(), lng.toDouble()]);
          }
        }
      }
      return result;
    }
    return const <List<double>>[];
  }

  bool _hasUnsavedCableChanges() {
    if (isEditingCable && before != null) {
      final current = _cableSnapshot(addingCable);
      final prev = _cableSnapshot(before);
      return jsonEncode(current) != jsonEncode(prev);
    }
    final points = addingCable.points ?? const <LatLng>[];
    final hasPoints = points.isNotEmpty;
    final hasComment = (addingCable.comment ?? '').trim().isNotEmpty;
    final hasFibers = addingCable.fibersNumber != null;
    return hasPoints || hasComment || hasFibers;
  }

  Future<bool> _confirmDiscardCableChanges() async {
    if (!_hasUnsavedCableChanges()) return true;
    final res = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Отменить изменения?'),
            content: const Text('Несохранённые изменения будут потеряны.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Остаться'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Отменить'),
              ),
            ],
          ),
    );
    return res == true;
  }

  Widget _buildModeIndicator() {
    String? label;
    if (mode.startsWith('addingcable')) {
      label = 'Добавление кабеля';
    } else if (mode == 'changePillar') {
      label = 'Перемещение опоры';
    } else if (mode == 'getpoint') {
      label = 'Выбор точки';
    }
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildRadiusIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Text('R:$showRadius м', style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildAddingCableHint() {
    final pointsCount = addingCable.points?.length ?? 0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timeline, size: 16),
              const SizedBox(width: 8),
              Text('Добавьте точки. Сейчас: $pointsCount'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastPointMarker() {
    final point = _lastAddedPoint;
    if (point == null) return const SizedBox.shrink();
    final key = ValueKey(_lastAddedTick);
    return MarkerLayer(
      markers: [
        Marker(
          width: 30,
          height: 30,
          point: point,
          builder:
              (context) => TweenAnimationBuilder<double>(
                key: key,
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 700),
                builder:
                    (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.6 + 0.6 * value,
                        child: child,
                      ),
                    ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.deepOrange, width: 2),
                  ),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildCableTapTargets(List<Cable> cables) {
    final markers = <Marker>[];
    for (final cable in cables) {
      final points = cable.points ?? const <LatLng>[];
      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final mid = LatLng(
          (p1.latitude + p2.latitude) / 2,
          (p1.longitude + p2.longitude) / 2,
        );
        markers.add(
          Marker(
            width: 26,
            height: 26,
            point: mid,
            builder:
                (context) => GestureDetector(
                  onTap: () => _startEditCable(cable),
                  child: Container(color: Colors.transparent),
                ),
          ),
        );
      }
    }
    if (markers.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(markers: markers);
  }

  @override
  void initState() {
    _resetPolyEditor();
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

    if (params.containsKey('getcable')) {
      setState(() {
        mode = 'addingcablegetcable';
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
          _buildRadiusIndicator(),
          _buildAddMenu(),
          _buildLayerToggle(),
          _buildModeIndicator(),
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
                print('FlutterMap.options onTap: $point');
                if (mode.startsWith('addingcable')) {
                  _handleTapForAddingCable(point);
                }
                _handleTap(point);
              },
            ),
            children: [
              if (isSatLayer) yandexMapSatTileLayer else yandexMapTileLayer,
              if (!mode.startsWith('addingcable')) _buildRadiusCircleLayer(),
              if (!mode.startsWith('addingcable')) _buildCenterMarker(),
              if (true) _buildPonBoxMarkers(),
              _buildPillarMarkers(),
              ..._buildCables(),
              if (!mode.startsWith('addingcable')) _buildCableTapTargets(cables),
              if (mode == 'changePillar') _buildLineFromOldPillarToCenter(),
              if (mode.startsWith('addingcable')) ..._buildAddingCable(),
              if (mode.startsWith('addingcable')) _buildLastPointMarker(),
            ],
          ),
          if (mode == 'changePillar') _buildPillarEditModeOverlay(),
          if (mode.startsWith('addingcable')) _buildCableEditModeOverlay(),
          if (mode.startsWith('addingcable')) _buildAddingCableHint(),
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
          case 'cable':
            _addCable();
            break;
        }
      },
      icon: const Icon(Icons.add),
      itemBuilder:
          (context) => [
            const PopupMenuItem(value: 'ponbox', child: Text('PON box')),
            //const PopupMenuItem(value: 'opora', child: Text('Опора')),
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
                      (context) => ponBoxWidget(ponBox, currentZoom),
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
                    color: fibers[cable.fibersNumber]!,
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
                              before = jsonDecode(jsonEncode(cable.toMap()));
                              setState(() {
                                mode = 'addingcableandchange';
                                addingCable = cable;
                                isEditingCable = true;
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
      PolylineLayer(polylines: [Polyline(points: addingCable.points ?? const [])]),
      DragMarkers(markers: polyEditor.edit()),
    ];
  }

  Widget _buildAddingCableActions() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: Icon(Icons.cancel),
            label: Text('Отмена'),
            onPressed: () async {
              final canDiscard = await _confirmDiscardCableChanges();
              if (!canDiscard) return;
              await loadCables();
              setState(() {
                mode = '';
                isEditingCable = false;
                before = null;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                final points = addingCable.points ?? const <LatLng>[];
                if (points.length < _minCablePoints) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Добавьте хотя бы две точки кабеля')),
                  );
                  return;
                }
                commentController.text = addingCable.comment ?? '';
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
                            TextField(
                              controller: commentController,
                            ),
                            Text('Укажите количество волокон в кабеле:'),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runSpacing: 10,
                              spacing: 10,
                              children: [
                                ...fibers.keys.map(
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
                if (dialogRes != null) {
                  fibersNumber = dialogRes;
                  addingCable.comment = commentController.text;
                } else {
                  return;
                }
                if (mode.contains('getcable')) {
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
                      jsonEncode(addingCable.toMap()).toJS,
                    );
                  }
                }
                print('save cable:\n $addingCable');
                addingCable.fibersNumber = fibersNumber;
                var res = await addingCable.storeCable(mode == 'addingcablenew' ? null : addingCable);
                print('[DB]:\n$res');
                if (res.isNotEmpty) {
                  setState(() {
                    addingCable.id = res.first['id'];
                    cables.add(addingCable);
                    print('save to history');
                    if (isEditingCable && before != null) {
                      addingCable
                          .updateCableHistory(before: before!)
                          .then((onValue) => print('[DB History result]\n$onValue'));
                    }
                    mode = '';
                    isEditingCable = false;
                    before = null;
                  });
                } else {
                  reportError('Ошибка сохранения кабеля');
                }
              },
              label: Text('Сохранить [${addingCable.cableLength()} м.]'),
            ),
          ),
        ],
      ),
    );
  }

  _handleTapForAddingCable(LatLng pos) {
    polyEditor.add(addingCable.points!, pos);
    setState(() {
      _lastAddedPoint = pos;
      _lastAddedTick++;
      _lastAddedTimer?.cancel();
      _lastAddedTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() {
          _lastAddedPoint = null;
        });
      });
    });
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

  /*
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
  }*/

  Future<void> _addCable() async {
    setState(() {
      addingCable = Cable(points: []);
      isEditingCable = false;
      before = null;
      _resetPolyEditor();
      mode = 'addingcablenew';
    });
  }

  void reportError(String s) {
    //show error message by scaffoldMessenger
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
  
  void _handleTap(LatLng point) {
    var resbox = ponBoxes.firstWhere((box) => Distance().distance(LatLng(box['lat'], box['long']), point) <= 6, orElse: () => {},);
    if (resbox.isNotEmpty) {
      showPonBoxInfoSheet(
        context,
        resbox,
        () => setState(() {}),
        currentMapCenter: currentCenter,
      );
    }
  }
}
