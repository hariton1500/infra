import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/Pages/muff_location_picker.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

class MuffNotebookPage extends StatefulWidget {
  const MuffNotebookPage({super.key});

  @override
  State<MuffNotebookPage> createState() => _MuffNotebookPageState();
}

class _MuffNotebookPageState extends State<MuffNotebookPage> {
  // Список муфт в памяти, отображается в UI (фильтрация/сортировка).
  final List<Map<String, dynamic>> _muffs = [];
  bool _loadingMuffs = true;
  Map<String, dynamic>? _selectedMuff;
  int? _selectedCableId;

  // Ключи/координаты для отрисовки линий соединений между волокнами.
  final GlobalKey _fiberAreaKey = GlobalKey();
  final Map<String, GlobalKey> _fiberKeys = {};
  Map<String, Offset> _fiberOffsets = {};
  final Set<String> _currentFiberKeys = {};
  final Map<String, Color> _fiberColorByKey = {};
  final Map<String, int> _fiberSideByKey = {};

  // Статус синхронизации с Supabase.
  bool _syncing = false;
  // Таймер авто-синхронизации.
  Timer? _syncTimer;
  // Режим отображения: список или карта.
  bool _mapView = false;
  // Контроллер карты и масштаб.
  final MapController _mapController = MapController();
  double _mapZoom = 14;

  static int _nextMuffId = 1;
  static final List<Map<String, dynamic>> _muffStore = [];
  static const String _muffsKey = 'muff_notebook.muffs';

  static const Map<String, List<Color>> _fiberSchemes = {
    'default': [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.brown,
      Colors.grey,
      Colors.white,
      Colors.red,
      Colors.black,
      Colors.yellow,
      Colors.purple,
      Colors.pink,
      Colors.cyan,
    ],
  };

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
    _startAutoSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final muffsRaw = prefs.getString(_muffsKey);
    _muffStore.clear();
    if (muffsRaw != null && muffsRaw.isNotEmpty) {
      _loadFromJson(muffsRaw);
    }

    final maxId =
        _muffStore.map((m) => (m['id'] as int?) ?? 0).fold(0, (a, b) => a > b ? a : b);
    _nextMuffId = maxId + 1;

    await _loadMuffs();
    try {
      await _pullMerge();
      await _persist();
      await _loadMuffs();
    } catch (_) {
      // Тихо игнорируем ошибки старта синка.
    }
  }

  String _serializeToJson() {
    // Сохранение в локальное хранилище в JSON (DateTime -> ISO).
    final muffsToSave = _muffStore.map((m) {
      final copy = Map<String, dynamic>.from(m);
      final updatedAt = copy['updated_at'];
      if (updatedAt is DateTime) {
        copy['updated_at'] = updatedAt.toIso8601String();
      }
      return copy;
    }).toList();
    return jsonEncode(muffsToSave);
  }

  void _loadFromJson(String jsonText) {
    // Загрузка JSON из локального хранилища в память.
    _muffStore.clear();
    final list = jsonDecode(jsonText) as List<dynamic>;
    for (final item in list) {
      final map = Map<String, dynamic>.from(item as Map);
      final updatedAt = map['updated_at'];
      if (updatedAt is String && updatedAt.isNotEmpty) {
        map['updated_at'] = DateTime.tryParse(updatedAt);
      }
      map['dirty'] = map['dirty'] == true;
      _muffStore.add(map);
    }
    final maxId =
        _muffStore.map((m) => (m['id'] as int?) ?? 0).fold(0, (a, b) => a > b ? a : b);
    _nextMuffId = maxId + 1;
  }

  Future<void> _persist() async {
    // Сохранение локального состояния в SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final jsonText = _serializeToJson();
    await prefs.setString(_muffsKey, jsonText);
  }

  Future<void> _loadMuffs() async {
    // Построение списка для UI (исключаем удалённые, сортировка по updated_at).
    setState(() => _loadingMuffs = true);
    _muffs
      ..clear()
      ..addAll(_muffStore.where((m) => m['deleted'] != true));
    _muffs.sort((a, b) {
      final aTime = a['updated_at'] as DateTime?;
      final bTime = b['updated_at'] as DateTime?;
      return (bTime ?? DateTime(1970)).compareTo(aTime ?? DateTime(1970));
    });
    if (mounted) setState(() => _loadingMuffs = false);
  }

  void _touchMuff(Map<String, dynamic> muff) {
    // Пометка локальных изменений (красный статус) и обновление времени.
    muff['updated_at'] = DateTime.now();
    muff['dirty'] = true;
  }

  Map<String, dynamic> _payloadForDb(Map<String, dynamic> muff) {
    // Подготовка payload для Supabase (без runtime-полей).
    final copy = Map<String, dynamic>.from(muff);
    copy.remove('dirty');
    copy.remove('deleted');
    return _jsonSafe(copy) as Map<String, dynamic>;
  }

  dynamic _jsonSafe(dynamic value) {
    // Глубокая конвертация в JSON-безопасную структуру.
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((k, v) {
        result[k.toString()] = _jsonSafe(v);
      });
      return result;
    }
    if (value is List) {
      return value.map(_jsonSafe).toList();
    }
    return value;
  }

  Future<void> _syncAll() async {
    // Отправка всех dirty-элементов в Supabase (tombstone для удалений).
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final dirty = _muffStore.where((m) => m['dirty'] == true).toList();
      for (final muff in dirty) {
        final id = muff['id'];
        final now = DateTime.now().toIso8601String();
        if (muff['deleted'] == true) {
          await sbMuffs.upsert({
            'id': id,
            'payload': null,
            'deleted': true,
            'updated_at': now,
            'synced_at': now,
            'updated_by': activeUser['login'],
          }, onConflict: 'id');
          _muffStore.remove(muff);
        } else {
          await sbMuffs.upsert({
            'id': id,
            'payload': _payloadForDb(muff),
            'deleted': false,
            'updated_at': now,
            'synced_at': now,
            'updated_by': activeUser['login'],
          }, onConflict: 'id');
          muff['dirty'] = false;
        }
      }
      await _pullMerge();
      await _persist();
      await _loadMuffs();
    } catch (e) {
      _showSnack('Ошибка синхронизации: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _startAutoSync() {
    // Авто-синхронизация раз в минуту.
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _syncAll());
  }

  DateTime _parseServerTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
  }

  Map<String, dynamic> _normalizePayload(dynamic payload) {
    // Приведение payload из БД к локальному формату.
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      final updatedAt = map['updated_at'];
      if (updatedAt is String && updatedAt.isNotEmpty) {
        map['updated_at'] = DateTime.tryParse(updatedAt);
      }
      map['dirty'] = false;
      return map;
    }
    return <String, dynamic>{};
  }

  Future<void> _pullMerge() async {
    // Подтягиваем серверные изменения и мержим в локальные данные.
    final res = await sbMuffs.select();
    final rows = List<Map<String, dynamic>>.from(res);
    for (final row in rows) {
      final id = row['id'];
      final serverDeleted = row['deleted'] == true;
      final serverUpdated = _parseServerTime(row['updated_at']);
      final localIndex = _muffStore.indexWhere((m) => m['id'] == id);

      if (localIndex == -1) {
        if (serverDeleted) continue;
        final payload = _normalizePayload(row['payload']);
        if (payload.isEmpty) continue;
        payload['id'] = id;
        _muffStore.add(payload);
        continue;
      }

      final local = _muffStore[localIndex];
      final localUpdated = (local['updated_at'] as DateTime?) ?? DateTime(1970);
      final localDirty = local['dirty'] == true;

      if (localDirty) {
        // Приоритет локальным изменениям.
        continue;
      }

      if (serverDeleted) {
        _muffStore.removeAt(localIndex);
        continue;
      }

      if (serverUpdated.isAfter(localUpdated)) {
        final payload = _normalizePayload(row['payload']);
        if (payload.isEmpty) continue;
        payload['id'] = id;
        _muffStore[localIndex] = payload;
      }
    }
  }

  void _scheduleFiberLayout() {
    // Снятие координат виджетов после layout для линий соединений.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final areaCtx = _fiberAreaKey.currentContext;
      if (areaCtx == null) return;
      final areaBox = areaCtx.findRenderObject() as RenderBox?;
      if (areaBox == null || !areaBox.hasSize) return;

      _fiberKeys.removeWhere((key, _) => !_currentFiberKeys.contains(key));

      final newOffsets = <String, Offset>{};
      for (final entry in _fiberKeys.entries) {
        final ctx = entry.value.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final side = _fiberSideByKey[entry.key] ?? 0;
        final edgeOffset = side == 0
            ? Offset(box.size.width, box.size.height / 2)
            : Offset(0, box.size.height / 2);
        final globalPoint = box.localToGlobal(edgeOffset);
        newOffsets[entry.key] = areaBox.globalToLocal(globalPoint);
      }

      bool changed = newOffsets.length != _fiberOffsets.length;
      if (!changed) {
        for (final entry in newOffsets.entries) {
          final prev = _fiberOffsets[entry.key];
          if (prev == null || (prev - entry.value).distanceSquared > 0.5) {
            changed = true;
            break;
          }
        }
      }

      if (changed && mounted) {
        setState(() => _fiberOffsets = newOffsets);
      }
    });
  }

  Future<void> _selectMuff(Map<String, dynamic> muff) async {
    setState(() {
      _selectedMuff = muff;
      _selectedCableId = null;
    });
  }

  Future<void> _showMuffEditor({Map<String, dynamic>? muff}) async {
    // Диалог создания/редактирования муфты (название, адрес, комментарий, точка).
    final nameController = TextEditingController(text: muff?['name'] ?? '');
    final locationController = TextEditingController(text: muff?['location'] ?? '');
    final commentController = TextEditingController(text: muff?['comment'] ?? '');
    double? lat = muff?['location_lat'] as double?;
    double? lng = muff?['location_lng'] as double?;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(muff == null ? 'Новая муфта' : 'Редактировать муфту'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Адрес/место'),
                    ),
                    TextField(
                      controller: commentController,
                      decoration: const InputDecoration(labelText: 'Комментарий'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.place, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            lat != null && lng != null
                                ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
                                : 'Геопозиция не задана',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final res = await Navigator.of(context).push<LatLng>(
                              MaterialPageRoute(
                                builder:
                                    (_) => MuffLocationPickerPage(
                                      initial:
                                          lat != null && lng != null
                                              ? LatLng(lat!, lng!)
                                              : null,
                                    ),
                              ),
                            );
                            if (res != null) {
                              setStateDialog(() {
                                lat = res.latitude;
                                lng = res.longitude;
                              });
                            }
                          },
                          icon: const Icon(Icons.map),
                          label: const Text('На карте'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final payload = <String, dynamic>{
                      'name': nameController.text.trim(),
                      'location': locationController.text.trim(),
                      'comment': commentController.text.trim(),
                      'location_lat': lat,
                      'location_lng': lng,
                      'updated_at': DateTime.now(),
                      'updated_by': activeUser['login'],
                    };

                    if (muff == null) {
                      payload['id'] = _nextMuffId++;
                      payload['created_by'] = activeUser['login'];
                      payload['cables'] = <Map<String, dynamic>>[];
                      payload['connections'] = <Map<String, dynamic>>[];
                      payload['dirty'] = true;
                      _muffStore.add(payload);
                    } else {
                      payload['id'] = muff['id'];
                      payload['created_by'] = muff['created_by'];
                      payload['cables'] = muff['cables'] ?? <Map<String, dynamic>>[];
                      payload['connections'] =
                          muff['connections'] ?? <Map<String, dynamic>>[];
                      payload['dirty'] = true;
                      final idx =
                          _muffStore.indexWhere((m) => m['id'] == muff['id']);
                      if (idx != -1) {
                        _muffStore[idx] = payload;
                      }
                    }

                    await _persist();
                    Navigator.of(context).pop();
                    await _loadMuffs();
                    await _selectMuff(payload);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteMuff(Map<String, dynamic> muff) async {
    // Мягкое удаление локально; окончательное удаление после синка.
    muff['deleted'] = true;
    _touchMuff(muff);
    await _persist();
    await _loadMuffs();
    if (_selectedMuff?['id'] == muff['id']) {
      setState(() => _selectedMuff = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _openMuffLocation(Map<String, dynamic> muff) async {
    // Открыть карту и сохранить координаты.
    final lat = muff['location_lat'] as double?;
    final lng = muff['location_lng'] as double?;
    final res = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder:
            (_) => MuffLocationPickerPage(
              initial: lat != null && lng != null ? LatLng(lat, lng) : null,
            ),
      ),
    );
    if (res != null) {
      muff['location_lat'] = res.latitude;
      muff['location_lng'] = res.longitude;
      _touchMuff(muff);
      await _persist();
      await _loadMuffs();
      setState(() {});
    }
  }


  Map<String, dynamic>? _getCableById(int id) {
    final muff = _selectedMuff;
    if (muff == null) return null;
    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    return cables.firstWhere((c) => c['id'] == id, orElse: () => {});
  }

  List<Map<String, dynamic>> _getCablesBySide(int side) {
    final muff = _selectedMuff;
    if (muff == null) return [];
    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    return cables.where((c) => (c['side'] as int? ?? 0) == side).toList();
  }

  Future<void> _addCable() async {
    // Добавление кабеля к муфте (сторона, волокна, маркировка).
    if (_selectedMuff == null) return;
    String name = '';
    int fibersNumber = 12;
    int side = 0;
    String scheme = _fiberSchemes.keys.first;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Добавить кабель'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: 'Направление/имя'),
                      onChanged: (v) => name = v,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Волокон:'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: fibersNumber,
                          items: [1, 2, 4, 8, 12, 24]
                              .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                              .toList(),
                          onChanged: (v) => setStateDialog(() => fibersNumber = v ?? 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Сторона:'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: side,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Слева')),
                            DropdownMenuItem(value: 1, child: Text('Справа')),
                          ],
                          onChanged: (v) => setStateDialog(() => side = v ?? 0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Маркировка:'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: scheme,
                          items: _fiberSchemes.keys
                              .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                              .toList(),
                          onChanged: (v) => setStateDialog(() => scheme = v ?? scheme),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final muff = _selectedMuff!;
                    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
                    final cable = <String, dynamic>{
                      'id': DateTime.now().microsecondsSinceEpoch,
                      'name': name.isEmpty ? 'Кабель' : name,
                      'fibers': fibersNumber,
                      'side': side,
                      'color_scheme': scheme,
                      'fiber_comments': List<String>.filled(fibersNumber, ''),
                      'spliters': List<int>.filled(fibersNumber, 0),
                    };
                    cables.add(cable);
                    muff['cables'] = cables;
                    _touchMuff(muff);
                    await _persist();
                    setState(() {});
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteCable(int cableId) async {
    // Удаление кабеля и его соединений.
    final muff = _selectedMuff;
    if (muff == null) return;
    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    cables.removeWhere((c) => c['id'] == cableId);
    muff['cables'] = cables;

    final connections = List<Map<String, dynamic>>.from(muff['connections'] ?? []);
    connections.removeWhere((c) => c['cable1'] == cableId || c['cable2'] == cableId);
    muff['connections'] = connections;

    _touchMuff(muff);
    if (_selectedCableId == cableId) _selectedCableId = null;
    await _persist();
    setState(() {});
  }

  Future<void> _editCableName(int cableId) async {
    // Переименование кабеля.
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return;
    final controller = TextEditingController(text: cable['name'] ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Редактировать имя кабеля'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                cable['name'] = controller.text.trim();
                if (_selectedMuff != null) _touchMuff(_selectedMuff!);
                await _persist();
                setState(() {});
                Navigator.of(context).pop();
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleCableSide(int cableId) async {
    // Перенос кабеля на другую сторону.
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return;
    final current = (cable['side'] as int?) ?? 0;
    cable['side'] = current == 0 ? 1 : 0;
    if (_selectedMuff != null) _touchMuff(_selectedMuff!);
    await _persist();
    setState(() {});
  }

  Future<void> _editFiber(int cableId, int fiberIndex) async {
    // Редактирование комментария волокна и сплиттера.
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return;
    final comments = List<String>.from(cable['fiber_comments'] ?? []);
    final spliters = List<int>.from(cable['spliters'] ?? []);
    if (fiberIndex >= comments.length || fiberIndex >= spliters.length) return;
    final commentController = TextEditingController(text: comments[fiberIndex]);
    int spliter = spliters[fiberIndex];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Кабель: ${cable['name']} | Волокно ${fiberIndex + 1}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(labelText: 'Комментарий'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Сплиттер:'),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: spliter,
                        items: [0, 2, 4, 8, 16, 32]
                            .map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? 'Нет' : '$v')))
                            .toList(),
                        onChanged: (v) => setStateSheet(() => spliter = v ?? 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          comments[fiberIndex] = commentController.text.trim();
                          spliters[fiberIndex] = spliter;
                          cable['fiber_comments'] = comments;
                          cable['spliters'] = spliters;
                          if (_selectedMuff != null) _touchMuff(_selectedMuff!);
                          await _persist();
                          setState(() {});
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addConnection() async {
    // Добавление соединения через диалог (волокно-волокно).
    final muff = _selectedMuff;
    if (muff == null) return;
    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    if (cables.length < 2) {
      _showSnack('Нужно минимум два кабеля');
      return;
    }
    int cable1 = cables.first['id'];
    int cable2 = cables.last['id'];
    int fiber1 = 0;
    int fiber2 = 0;

    List<DropdownMenuItem<int>> cableItems() => cables
        .map((c) => DropdownMenuItem<int>(
              value: c['id'],
              child: Text(c['name'] ?? 'Кабель'),
            ))
        .toList();

    List<DropdownMenuItem<int>> fiberItems(int cableId) {
      final cable = cables.firstWhere((c) => c['id'] == cableId);
      final count = (cable['fibers'] as int?) ?? 1;
      return List.generate(
        count,
        (i) => DropdownMenuItem(value: i, child: Text('${i + 1}')),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Добавить соединение'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('От:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      DropdownButton<int>(
                        value: cable1,
                        items: cableItems(),
                        onChanged: (v) => setStateDialog(() {
                          cable1 = v ?? cable1;
                          fiber1 = 0;
                        }),
                      ),
                      DropdownButton<int>(
                        value: fiber1,
                        items: fiberItems(cable1),
                        onChanged: (v) => setStateDialog(() => fiber1 = v ?? 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Куда:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      DropdownButton<int>(
                        value: cable2,
                        items: cableItems(),
                        onChanged: (v) => setStateDialog(() {
                          cable2 = v ?? cable2;
                          fiber2 = 0;
                        }),
                      ),
                      DropdownButton<int>(
                        value: fiber2,
                        items: fiberItems(cable2),
                        onChanged: (v) => setStateDialog(() => fiber2 = v ?? 0),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final connections =
                        List<Map<String, dynamic>>.from(muff['connections'] ?? []);
                    if (_isFiberBusy(connections, cable1, fiber1) ||
                        _isFiberBusy(connections, cable2, fiber2)) {
                      _showSnack('Волокно уже используется (без сплиттера)');
                      return;
                    }
                    final exists = connections.any((c) {
                      final c1 = c['cable1'];
                      final f1 = c['fiber1'];
                      final c2 = c['cable2'];
                      final f2 = c['fiber2'];
                      final same =
                          c1 == cable1 && f1 == fiber1 && c2 == cable2 && f2 == fiber2;
                      final reverse =
                          c1 == cable2 && f1 == fiber2 && c2 == cable1 && f2 == fiber1;
                      return same || reverse;
                    });
                    if (exists) {
                      _showSnack('Такое соединение уже есть');
                      return;
                    }
                    connections.add({
                      'cable1': cable1,
                      'fiber1': fiber1,
                      'cable2': cable2,
                      'fiber2': fiber2,
                    });
                    muff['connections'] = connections;
                    _touchMuff(muff);
                    await _persist();
                    setState(() {});
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addConnectionDirect({
    required int cable1,
    required int fiber1,
    required int cable2,
    required int fiber2,
  }) async {
    // Добавление соединения через drag&drop (волокно-волокно).
    final muff = _selectedMuff;
    if (muff == null) return;
    if (cable1 == cable2) {
      _showSnack('Нельзя соединять волокна одного кабеля');
      return;
    }
    final connections = List<Map<String, dynamic>>.from(muff['connections'] ?? []);
    if (_isFiberBusy(connections, cable1, fiber1) ||
        _isFiberBusy(connections, cable2, fiber2)) {
      _showSnack('Волокно уже используется (без сплиттера)');
      return;
    }
    final exists = connections.any((c) {
      final c1 = c['cable1'];
      final f1 = c['fiber1'];
      final c2 = c['cable2'];
      final f2 = c['fiber2'];
      final same = c1 == cable1 && f1 == fiber1 && c2 == cable2 && f2 == fiber2;
      final reverse = c1 == cable2 && f1 == fiber2 && c2 == cable1 && f2 == fiber1;
      return same || reverse;
    });
    if (exists) {
      _showSnack('Такое соединение уже есть');
      return;
    }
    connections.add({
      'cable1': cable1,
      'fiber1': fiber1,
      'cable2': cable2,
      'fiber2': fiber2,
    });
    muff['connections'] = connections;
    _touchMuff(muff);
    await _persist();
    setState(() {});
  }

  void _showSnack(String message) {
    if (!mounted) return;
    print(message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _statusDot(bool dirty) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: dirty ? Colors.red : Colors.green,
        shape: BoxShape.circle,
      ),
    );
  }

  bool _isFiberBusy(
    List<Map<String, dynamic>> connections,
    int cableId,
    int fiberIndex,
  ) {
    // Запрет множественных соединений для волокна без сплиттера.
    final hasSpliter = _fiberHasSpliter(cableId, fiberIndex);
    if (hasSpliter) return false;
    return connections.any((c) {
      final c1 = c['cable1'];
      final f1 = c['fiber1'];
      final c2 = c['cable2'];
      final f2 = c['fiber2'];
      return (c1 == cableId && f1 == fiberIndex) ||
          (c2 == cableId && f2 == fiberIndex);
    });
  }

  bool _fiberHasSpliter(int cableId, int fiberIndex) {
    // Наличие сплиттера разрешает множественные соединения.
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return false;
    final spliters = List<int>.from(cable['spliters'] ?? []);
    if (fiberIndex < 0 || fiberIndex >= spliters.length) return false;
    return spliters[fiberIndex] > 0;
  }

  @override
  Widget build(BuildContext context) {
    // Основной layout: статус синка и панели списка/деталей.
    final hasDirty =
        _muffStore.any((m) => m['deleted'] != true && m['dirty'] == true);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Блокнот муфт'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _mapView = !_mapView),
            icon: Icon(_mapView ? Icons.list : Icons.map),
            tooltip: _mapView ? 'Список' : 'Карта',
          ),
          IconButton(
            onPressed: _loadMuffs,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              onPressed: _syncAll,
              icon: Icon(Icons.cloud_upload, color: hasDirty ? Colors.red : Colors.green),
              tooltip: 'Синхронизировать',
            ),
          IconButton(
            onPressed: () => _showMuffEditor(),
            icon: const Icon(Icons.add),
            tooltip: 'Новая муфта',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_mapView) {
            return _buildMapPane();
          }
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                SizedBox(width: 320, child: _buildListPane()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildDetailPane()),
              ],
            );
          }
          return _selectedMuff == null
              ? _buildListPane()
              : _buildDetailPane(showBack: true);
        },
      ),
    );
  }

  Widget _buildMapPane() {
    // Карта муфт с маркерами.
    final muffsWithCoords =
        _muffs.where((m) => m['location_lat'] != null && m['location_lng'] != null).toList();
    final center = muffsWithCoords.isNotEmpty
        ? LatLng(
            muffsWithCoords.first['location_lat'] as double,
            muffsWithCoords.first['location_lng'] as double,
          )
        : const LatLng(55.751244, 37.618423);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        center: center,
        zoom: _mapZoom,
        maxZoom: 19,
        onPositionChanged: (pos, _) {
          if (pos.zoom != null) _mapZoom = pos.zoom!;
        },
      ),
      children: [
        yandexMapTileLayer,
        MarkerLayer(
          markers:
              muffsWithCoords.map((muff) {
                final point = LatLng(
                  muff['location_lat'] as double,
                  muff['location_lng'] as double,
                );
                return Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  builder:
                      (context) => GestureDetector(
                        onTap: () => _showMuffFromMap(muff),
                        child: const Icon(Icons.place, color: Colors.red, size: 32),
                      ),
                );
              }).toList(),
        ),
      ],
    );
  }

  void _showMuffFromMap(Map<String, dynamic> muff) {
    // Быстрый просмотр муфты из карты.
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                muff['name'] ?? 'Без названия',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(muff['location'] ?? ''),
              const SizedBox(height: 6),
              Text(
                '${(muff['location_lat'] as double).toStringAsFixed(6)}, '
                '${(muff['location_lng'] as double).toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Закрыть'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedMuff = muff;
                        _mapView = false;
                      });
                      Navigator.of(context).pop();
                    },
                    child: const Text('Открыть'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListPane() {
    // Левая панель: список муфт с индикатором синка.
    if (_loadingMuffs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_muffs.isEmpty) {
      return Center(
        child: Text(
          'Муфт пока нет. Добавьте первую запись.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _muffs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final muff = _muffs[index];
        final selected = _selectedMuff?['id'] == muff['id'];
        return Card(
          color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            leading: _statusDot(muff['dirty'] == true),
            title: Text(muff['name'] ?? 'Без названия'),
            subtitle: Text(muff['location'] ?? ''),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _showMuffEditor(muff: muff);
                if (v == 'geo') _openMuffLocation(muff);
                if (v == 'delete') _deleteMuff(muff);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                PopupMenuItem(value: 'geo', child: Text('Геопозиция')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
            onTap: () => _selectMuff(muff),
          ),
        );
      },
    );
  }

  Widget _buildDetailPane({bool showBack = false}) {
    // Правая панель: детали муфты, кабели, волокна, соединения.
    if (_selectedMuff == null) {
      return Center(
        child: Text(
          'Выберите муфту слева',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final muff = _selectedMuff!;
    final connections = List<Map<String, dynamic>>.from(muff['connections'] ?? []);
    _currentFiberKeys.clear();
    _fiberColorByKey.clear();
    _fiberSideByKey.clear();
    _scheduleFiberLayout();

    return SingleChildScrollView(
      child: Column(
        children: [
          if (showBack)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectedMuff = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('К списку'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(muff['dirty'] == true),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            muff['name'] ?? 'Без названия',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Геопозиция',
                          onPressed: () async {
                            final lat = muff['location_lat'] as double?;
                            final lng = muff['location_lng'] as double?;
                            final res = await Navigator.of(context).push<LatLng>(
                              MaterialPageRoute(
                                builder:
                                    (_) => MuffLocationPickerPage(
                                      initial:
                                          lat != null && lng != null
                                              ? LatLng(lat, lng)
                                              : null,
                                    ),
                              ),
                            );
                            if (res != null) {
                              muff['location_lat'] = res.latitude;
                              muff['location_lng'] = res.longitude;
                              _touchMuff(muff);
                              await _persist();
                              await _loadMuffs();
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.map),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(muff['location'] ?? ''),
                    if (muff['location_lat'] != null && muff['location_lng'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.place, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${(muff['location_lat'] as double).toStringAsFixed(6)}, '
                              '${(muff['location_lng'] as double).toStringAsFixed(6)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () async {
                                final res = await Navigator.of(context).push<LatLng>(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => MuffLocationPickerPage(
                                          initial: LatLng(
                                            muff['location_lat'] as double,
                                            muff['location_lng'] as double,
                                          ),
                                        ),
                                  ),
                                );
                                if (res != null) {
                                  muff['location_lat'] = res.latitude;
                                  muff['location_lng'] = res.longitude;
                                  _touchMuff(muff);
                                  await _persist();
                                  await _loadMuffs();
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.map),
                              label: const Text('Изменить'),
                            ),
                          ],
                        ),
                      ),
                    if ((muff['comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(muff['comment']),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Кабели', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addCable,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить кабель'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              key: _fiberAreaKey,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildCableColumn(0)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildCableColumn(1)),
                  ],
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConnectionsPainter(
                        connections: connections,
                        positions: _fiberOffsets,
                        colors: _fiberColorByKey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_selectedCableId != null) _buildSelectedCableDetails(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Соединения', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addConnection,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
                if (connections.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      muff['connections'] = <Map<String, dynamic>>[];
                      _touchMuff(muff);
                      await _persist();
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Очистить все'),
                  ),
              ],
            ),
          ),
          if (connections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Соединений пока нет'),
            )
          else
            Column(
              children: connections.map((c) {
                final cable1 = _getCableById(c['cable1']);
                final cable2 = _getCableById(c['cable2']);
                return ListTile(
                  dense: true,
                  leading: IconButton(
                    onPressed: () async {
                      connections.remove(c);
                      muff['connections'] = connections;
                      _touchMuff(muff);
                      await _persist();
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                  title: Text(
                    '${cable1?['name'] ?? 'Кабель'}[${(c['fiber1'] as int) + 1}] '
                    '<--> ${cable2?['name'] ?? 'Кабель'}[${(c['fiber2'] as int) + 1}]',
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCableColumn(int side) {
    // Список кабелей стороны с вертикальной колонкой волокон и drag-целями.
    final cables = _getCablesBySide(side);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(side == 0 ? 'Слева' : 'Справа', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (cables.isEmpty)
          const Text('Нет кабелей'),
        ...cables.map((cable) {
          final isSelected = _selectedCableId == cable['id'];
          return Card(
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
            child: InkWell(
              onTap: () => setState(() => _selectedCableId = cable['id']),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cable['name'] ?? 'Кабель',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') _editCableName(cable['id']);
                            if (v == 'swap') _toggleCableSide(cable['id']);
                            if (v == 'delete') _deleteCable(cable['id']);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                            PopupMenuItem(value: 'swap', child: Text('Перенести на другую сторону')),
                            PopupMenuItem(value: 'delete', child: Text('Удалить')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate((cable['fibers'] as int?) ?? 1, (i) {
                        final scheme = cable['color_scheme'] ?? 'default';
                        final colors = _fiberSchemes[scheme] ?? _fiberSchemes.values.first;
                        final color = colors[i % colors.length];
                        final spliters = List<int>.from(cable['spliters'] ?? []);
                        final spliter = i < spliters.length ? spliters[i] : 0;
                        final keyId = _fiberKey(cable['id'], i);
                        _currentFiberKeys.add(keyId);
                        _fiberColorByKey[keyId] = color;
                        _fiberSideByKey[keyId] = side;
                        final anchorKey =
                            _fiberKeys.putIfAbsent(keyId, () => GlobalKey());
                        final fiberWidget = DragTarget<Map<String, int>>(
                          onWillAcceptWithDetails: (_) => true,
                          onAcceptWithDetails: (details) {
                            final data = details.data;
                            _addConnectionDirect(
                              cable1: data['cableId']!,
                              fiber1: data['fiberIndex']!,
                              cable2: cable['id'],
                              fiber2: i,
                            );
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isHover = candidateData.isNotEmpty;
                            return Draggable<Map<String, int>>(
                              data: {
                                'cableId': cable['id'],
                                'fiberIndex': i,
                              },
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color == Colors.black ? Colors.white : Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: _fiberCircle(color, i + 1, isHover),
                              ),
                              child: GestureDetector(
                                onTap: () => _editFiber(cable['id'], i),
                                child: _fiberCircle(
                                  color,
                                  i + 1,
                                  isHover,
                                  key: spliter > 0 ? null : anchorKey,
                                ),
                              ),
                            );
                          },
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (side == 1 && spliter > 0)
                                _spliterBadge(spliter, key: anchorKey),
                              if (side == 1 && spliter > 0) const SizedBox(width: 6),
                              fiberWidget,
                              if (side == 0 && spliter > 0) const SizedBox(width: 6),
                              if (side == 0 && spliter > 0)
                                _spliterBadge(spliter, key: anchorKey),
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _fiberCircle(Color color, int label, bool highlight, {Key? key}) {
    // Визуальный элемент волокна (кружок).
    return Container(
      key: key,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: highlight ? Colors.deepOrange : Colors.black,
          width: highlight ? 2 : 1,
        ),
        boxShadow: highlight
            ? [BoxShadow(color: Colors.deepOrange.withValues(alpha: 0.5), blurRadius: 6)]
            : null,
      ),
      child: Center(
        child: Text(
          '$label',
          style: TextStyle(
            fontSize: 11,
            color: color == Colors.black ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _spliterBadge(int spliter, {Key? key}) {
    // Бейдж сплиттера рядом с волокном.
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '1:$spliter',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }

  Widget _buildSelectedCableDetails() {
    // Показ комментариев и сплиттеров для выбранного кабеля.
    final cable = _getCableById(_selectedCableId!);
    if (cable == null || cable.isEmpty) return const SizedBox.shrink();
    final comments = List<String>.from(cable['fiber_comments'] ?? []);
    final spliters = List<int>.from(cable['spliters'] ?? []);

    final commentItems = comments
        .asMap()
        .entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => Row(children: [
              Text('[${e.key + 1}]: '),
              Text(e.value),
            ]))
        .toList();

    final spliterItems = spliters
        .asMap()
        .entries
        .where((e) => e.value != 0)
        .map((e) => Row(children: [
              Text('[${e.key + 1}]: '),
              Text('Сплиттер ${e.value}'),
            ]))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Кабель: ${cable['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (commentItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Комментарии по волокнам:'),
            ...commentItems,
          ],
          if (spliterItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Сплиттеры:'),
            ...spliterItems,
          ],
        ],
      ),
    );
  }
}

class _ConnectionsPainter extends CustomPainter {
  final List<Map<String, dynamic>> connections;
  final Map<String, Offset> positions;
  final Map<String, Color> colors;

  _ConnectionsPainter({
    required this.connections,
    required this.positions,
    required this.colors,
  });

  String _key(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (final conn in connections) {
      final c1 = conn['cable1'] as int?;
      final f1 = conn['fiber1'] as int?;
      final c2 = conn['cable2'] as int?;
      final f2 = conn['fiber2'] as int?;
      if (c1 == null || f1 == null || c2 == null || f2 == null) continue;

      final p1 = positions[_key(c1, f1)];
      final p2 = positions[_key(c2, f2)];
      if (p1 == null || p2 == null) continue;

      paint.color = (colors[_key(c1, f1)] ?? Colors.deepOrange).withValues(alpha: 0.75);

      final midX = (p1.dx + p2.dx) / 2;
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(midX, p1.dy, midX, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);

      final dotPaint = Paint()..color = paint.color;
      canvas.drawCircle(p1, 3, dotPaint);
      canvas.drawCircle(p2, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.positions != positions ||
        oldDelegate.colors != colors;
  }
}
