import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/Pages/muff_location_picker.dart';
import 'package:infra/globals.dart';
import 'package:infra/misc/tile_providers.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

class CabinetNotebookPage extends StatefulWidget {
  const CabinetNotebookPage({super.key});

  @override
  State<CabinetNotebookPage> createState() => _CabinetNotebookPageState();
}

class _CabinetNotebookPageState extends State<CabinetNotebookPage> {
  final List<Map<String, dynamic>> _cabinets = [];
  bool _loadingCabinets = true;
  Map<String, dynamic>? _selectedCabinet;
  int? _selectedCableId;

  final GlobalKey _fiberAreaKey = GlobalKey();
  final Map<String, GlobalKey> _fiberKeys = {};
  Map<String, Offset> _fiberOffsets = {};
  final Set<String> _currentFiberKeys = {};
  final Map<String, Color> _fiberColorByKey = {};
  final Map<String, int> _fiberSideByKey = {};

  bool _syncing = false;
  Timer? _syncTimer;
  bool _mapView = false;
  final MapController _mapController = MapController();
  double _mapZoom = 14;

  static const int _version = 1;
  static int _nextCabinetId = 1;
  static final List<Map<String, dynamic>> _cabinetStore = [];
  static const String _cabinetsKey = 'cabinet_notebook.cabinets';

  static const Map<String, List<Color>> _fiberSchemes = {
    'default': [
      Colors.blue, Colors.orange, Colors.green, Colors.brown,
      Colors.grey, Colors.white, Colors.red, Colors.black,
      Colors.yellow, Colors.purple, Colors.pink, Colors.cyan,
    ],
    'odessa': [
      Colors.red, Colors.green, Colors.blue, Colors.yellow,
      Colors.white, Colors.grey, Colors.brown, Colors.purple,
      Colors.orange, Colors.black, Colors.pink, Colors.cyan,
    ],
  };

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';
  String _portKey(int switchId, int portIndex) => 's$switchId:$portIndex';

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
    final raw = prefs.getString(_cabinetsKey);
    _cabinetStore.clear();
    if (raw != null && raw.isNotEmpty) _loadFromJson(raw);

    final maxId = _cabinetStore.map((c) => (c['id'] as int?) ?? 0).fold(0, (a, b) => a > b ? a : b);
    _nextCabinetId = maxId + 1;
    await _loadCabinets();
    try {
      if (!_cabinetStore.any((c) => c['dirty'] == true)) await _pullMerge();
      await _persist();
      await _loadCabinets();
    } catch (_) {}
  }

  String _serializeToJson() {
    final toSave = _cabinetStore.map((c) {
      final copy = Map<String, dynamic>.from(c);
      final t = copy['updated_at'];
      if (t is DateTime) copy['updated_at'] = t.toIso8601String();
      return copy;
    }).toList();
    return jsonEncode(toSave);
  }

  void _loadFromJson(String text) {
    _cabinetStore.clear();
    final list = jsonDecode(text) as List<dynamic>;
    for (final item in list) {
      final map = Map<String, dynamic>.from(item as Map);
      final t = map['updated_at'];
      if (t is String && t.isNotEmpty) map['updated_at'] = DateTime.tryParse(t);
      map['dirty'] = map['dirty'] == true;
      _cabinetStore.add(map);
    }
    final maxId = _cabinetStore.map((c) => (c['id'] as int?) ?? 0).fold(0, (a, b) => a > b ? a : b);
    _nextCabinetId = maxId + 1;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cabinetsKey, _serializeToJson());
  }

  Future<void> _loadCabinets() async {
    setState(() => _loadingCabinets = true);
    _cabinets
      ..clear()
      ..addAll(_cabinetStore.where((c) => c['deleted'] != true));
    _cabinets.sort((a, b) {
      final at = (a['updated_at'] as DateTime?) ?? DateTime(1970);
      final bt = (b['updated_at'] as DateTime?) ?? DateTime(1970);
      return bt.compareTo(at);
    });
    if (mounted) setState(() => _loadingCabinets = false);
  }

  void _touchCabinet(Map<String, dynamic> cabinet) {
    cabinet['updated_at'] = DateTime.now();
    cabinet['dirty'] = true;
  }

  Map<String, dynamic> _payloadForDb(Map<String, dynamic> cabinet) {
    final copy = Map<String, dynamic>.from(cabinet);
    copy.remove('dirty');
    copy.remove('deleted');
    return _jsonSafe(copy) as Map<String, dynamic>;
  }

  dynamic _jsonSafe(dynamic v) {
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    if (v is List) return v.map(_jsonSafe).toList();
    return v;
  }

  Future<void> _syncAll() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final dirty = _cabinetStore.where((c) => c['dirty'] == true).toList();
      final justUpsertedIds = <int>{};
      for (final cabinet in dirty) {
        final id = cabinet['id'] as int;
        final now = DateTime.now().toIso8601String();
        if (cabinet['deleted'] == true) {
          await sbCabinets.upsert({
            'id': id,
            'payload': null,
            'deleted': true,
            'updated_at': now,
            'synced_at': now,
            'updated_by': activeUser['login'],
          }, onConflict: 'id').select();
          _cabinetStore.remove(cabinet);
        } else {
          await sbCabinets.upsert({
            'id': id,
            'payload': _payloadForDb(cabinet),
            'deleted': false,
            'updated_at': now,
            'synced_at': now,
            'updated_by': activeUser['login'],
          }, onConflict: 'id').select();
          cabinet['dirty'] = false;
          justUpsertedIds.add(id);
        }
      }
      if (!_cabinetStore.any((c) => c['dirty'] == true)) {
        await _pullMerge(skipReplaceIds: justUpsertedIds);
      }
      await _persist();
      await _loadCabinets();
    } catch (e) {
      _showSnack('Ошибка синхронизации: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _syncAll());
  }

  DateTime _parseServerTime(dynamic v) {
    if (v is DateTime) return v;
    return DateTime.tryParse(v?.toString() ?? '') ?? DateTime(1970);
  }

  Map<String, dynamic> _normalizePayload(dynamic p) {
    if (p is Map) {
      final map = Map<String, dynamic>.from(p);
      final t = map['updated_at'];
      if (t is String && t.isNotEmpty) map['updated_at'] = DateTime.tryParse(t);
      map['dirty'] = false;
      return map;
    }
    return <String, dynamic>{};
  }

  Future<void> _pullMerge({Set<int>? skipReplaceIds}) async {
    final res = await sbCabinets.select();
    final rows = List<Map<String, dynamic>>.from(res);
    for (final row in rows) {
      final id = row['id'];
      final serverDeleted = row['deleted'] == true;
      final serverUpdated = _parseServerTime(row['updated_at']);
      final idx = _cabinetStore.indexWhere((c) => c['id'] == id);
      if (idx == -1) {
        if (serverDeleted) continue;
        final payload = _normalizePayload(row['payload']);
        if (payload.isEmpty) continue;
        payload['id'] = id;
        _cabinetStore.add(payload);
        continue;
      }
      final local = _cabinetStore[idx];
      if (local['dirty'] == true) continue;
      if (serverDeleted) {
        _cabinetStore.removeAt(idx);
        continue;
      }
      if (skipReplaceIds?.contains(id) == true) continue;
      if (serverUpdated.isAfter((local['updated_at'] as DateTime?) ?? DateTime(1970))) {
        final payload = _normalizePayload(row['payload']);
        if (payload.isEmpty) continue;
        payload['id'] = id;
        _cabinetStore[idx] = payload;
      }
    }
  }

  void _scheduleFiberLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _fiberAreaKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      _fiberKeys.removeWhere((k, _) => !_currentFiberKeys.contains(k));
      final newOffsets = <String, Offset>{};
      for (final e in _fiberKeys.entries) {
        final c = e.value.currentContext;
        if (c == null) continue;
        final b = c.findRenderObject() as RenderBox?;
        if (b == null || !b.hasSize) continue;
        Offset off;
        if (e.key.startsWith('s')) {
          off = Offset(b.size.width / 2, b.size.height / 2);
        } else {
          final side = _fiberSideByKey[e.key] ?? 0;
          off = side == 0
              ? Offset(b.size.width, b.size.height / 2)
              : Offset(0, b.size.height / 2);
        }
        newOffsets[e.key] = box.globalToLocal(b.localToGlobal(off));
      }
      bool changed = newOffsets.length != _fiberOffsets.length ||
          newOffsets.entries.any((e) {
            final prev = _fiberOffsets[e.key];
            return prev == null || (prev - e.value).distanceSquared > 0.5;
          });
      if (changed && mounted) setState(() => _fiberOffsets = newOffsets);
    });
  }

  Future<void> _selectCabinet(Map<String, dynamic> cabinet) async {
    setState(() {
      _selectedCabinet = cabinet;
      _selectedCableId = null;
    });
  }

  Future<void> _showCabinetEditor({Map<String, dynamic>? cabinet}) async {
    final nameCtrl = TextEditingController(text: cabinet?['name'] ?? '');
    final locCtrl = TextEditingController(text: cabinet?['location'] ?? '');
    final commCtrl = TextEditingController(text: cabinet?['comment'] ?? '');
    double? lat = cabinet?['location_lat'] as double?;
    double? lng = cabinet?['location_lng'] as double?;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(cabinet == null ? 'Новый шкаф' : 'Редактировать шкаф'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название')),
                TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Адрес/место')),
                TextField(controller: commCtrl, decoration: const InputDecoration(labelText: 'Комментарий'), maxLines: 2),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.place, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lat != null && lng != null ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}' : 'Геопозиция не задана',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final r = await Navigator.of(context).push<LatLng>(
                          MaterialPageRoute(builder: (_) => MuffLocationPickerPage(initial: lat != null && lng != null ? LatLng(lat!, lng!) : null)),
                        );
                        if (r != null) setDlg(() { lat = r.latitude; lng = r.longitude; });
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
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            ElevatedButton.icon(
              onPressed: () async {
                final payload = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'location': locCtrl.text.trim(),
                  'comment': commCtrl.text.trim(),
                  'location_lat': lat,
                  'location_lng': lng,
                  'updated_at': DateTime.now(),
                  'updated_by': activeUser['login'],
                };
                if (cabinet == null) {
                  payload['id'] = _nextCabinetId++;
                  payload['created_by'] = activeUser['login'];
                  payload['switches'] = <Map<String, dynamic>>[];
                  payload['cables'] = <Map<String, dynamic>>[];
                  payload['connections'] = <Map<String, dynamic>>[];
                  payload['dirty'] = true;
                  _cabinetStore.add(payload);
                } else {
                  payload['id'] = cabinet['id'];
                  payload['created_by'] = cabinet['created_by'];
                  payload['switches'] = cabinet['switches'] ?? <Map<String, dynamic>>[];
                  payload['cables'] = cabinet['cables'] ?? <Map<String, dynamic>>[];
                  payload['connections'] = cabinet['connections'] ?? <Map<String, dynamic>>[];
                  payload['dirty'] = true;
                  final i = _cabinetStore.indexWhere((c) => c['id'] == cabinet['id']);
                  if (i >= 0) _cabinetStore[i] = payload;
                }
                await _persist();
                Navigator.of(context).pop();
                await _loadCabinets();
                await _selectCabinet(payload);
              },
              icon: const Icon(Icons.save),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCabinet(Map<String, dynamic> cabinet) async {
    cabinet['deleted'] = true;
    _touchCabinet(cabinet);
    await _persist();
    await _loadCabinets();
    if (_selectedCabinet?['id'] == cabinet['id']) setState(() => _selectedCabinet = null);
    setState(() {});
  }

  Future<void> _openCabinetLocation(Map<String, dynamic> cabinet) async {
    final lat = cabinet['location_lat'] as double?;
    final lng = cabinet['location_lng'] as double?;
    final r = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MuffLocationPickerPage(initial: lat != null && lng != null ? LatLng(lat, lng) : null)),
    );
    if (r != null) {
      cabinet['location_lat'] = r.latitude;
      cabinet['location_lng'] = r.longitude;
      _touchCabinet(cabinet);
      await _persist();
      await _loadCabinets();
      setState(() {});
    }
  }

  Map<String, dynamic>? _getCableById(int id) {
    final cab = _selectedCabinet;
    if (cab == null) return null;
    final cables = List<Map<String, dynamic>>.from(cab['cables'] ?? []);
    try {
      return cables.firstWhere((c) => c['id'] == id);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _getCablesBySide(int side) {
    final cab = _selectedCabinet;
    if (cab == null) return [];
    final cables = List<Map<String, dynamic>>.from(cab['cables'] ?? []);
    return cables.where((c) => (c['side'] as int? ?? 0) == side).toList();
  }

  Map<String, dynamic>? _getSwitchById(int id) {
    final cab = _selectedCabinet;
    if (cab == null) return null;
    final sw = List<Map<String, dynamic>>.from(cab['switches'] ?? []);
    try {
      return sw.firstWhere((s) => s['id'] == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _addSwitch() async {
    if (_selectedCabinet == null) return;
    final nameCtrl = TextEditingController(text: 'Коммутатор');
    final modelCtrl = TextEditingController();
    int ports = 24;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Добавить коммутатор'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                TextField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(labelText: 'Модель'),
                ),
                Row(
                  children: [
                    const Text('Портов:'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: ports,
                      items: [8, 10, 16, 24, 26, 28, 34, 48].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                      onChanged: (v) => setDlg(() => ports = v ?? 24),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            ElevatedButton.icon(
              onPressed: () async {
                final cab = _selectedCabinet!;
                final sw = List<Map<String, dynamic>>.from(cab['switches'] ?? []);
                sw.add({
                  'id': DateTime.now().microsecondsSinceEpoch,
                  'name': nameCtrl.text.trim().isEmpty ? 'Коммутатор' : nameCtrl.text.trim(),
                  'model': modelCtrl.text.trim(),
                  'ports': ports,
                });
                cab['switches'] = sw;
                _touchCabinet(cab);
                await _persist();
                setState(() {});
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSwitch(int switchId) async {
    final cab = _selectedCabinet;
    if (cab == null) return;
    final sw = List<Map<String, dynamic>>.from(cab['switches'] ?? []);
    sw.removeWhere((s) => s['id'] == switchId);
    cab['switches'] = sw;
    final conn = List<Map<String, dynamic>>.from(cab['connections'] ?? []);
    conn.removeWhere((c) => c['switch1'] == switchId || c['switch2'] == switchId);
    cab['connections'] = conn;
    _touchCabinet(cab);
    await _persist();
    setState(() {});
  }

  Future<void> _addCable() async {
    if (_selectedCabinet == null) return;
    String name = '';
    int fibersNumber = 12;
    int side = 0;
    String scheme = _fiberSchemes.keys.first;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Добавить кабель'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(decoration: const InputDecoration(labelText: 'Направление/имя'), onChanged: (v) => name = v),
                Row(children: [
                  const Text('Волокон:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: fibersNumber,
                    items: [1, 2, 4, 8, 12, 16, 24, 32, 48, 64, 96].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                    onChanged: (v) => setDlg(() => fibersNumber = v ?? 12),
                  ),
                ]),
                Row(children: [
                  const Text('Сторона:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: side,
                    items: const [DropdownMenuItem(value: 0, child: Text('Слева')), DropdownMenuItem(value: 1, child: Text('Справа'))],
                    onChanged: (v) => setDlg(() => side = v ?? 0),
                  ),
                ]),
                Row(children: [
                  const Text('Маркировка:'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: scheme,
                    items: _fiberSchemes.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                    onChanged: (v) => setDlg(() => scheme = v ?? scheme),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            ElevatedButton.icon(
              onPressed: () async {
                final cab = _selectedCabinet!;
                final cables = List<Map<String, dynamic>>.from(cab['cables'] ?? []);
                cables.add({
                  'id': DateTime.now().microsecondsSinceEpoch,
                  'name': name.isEmpty ? 'Кабель' : name,
                  'fibers': fibersNumber,
                  'side': side,
                  'color_scheme': scheme,
                  'fiber_comments': List<String>.filled(fibersNumber, ''),
                  'spliters': List<int>.filled(fibersNumber, 0),
                });
                cab['cables'] = cables;
                _touchCabinet(cab);
                await _persist();
                setState(() {});
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCable(int cableId) async {
    final cab = _selectedCabinet;
    if (cab == null) return;
    final cables = List<Map<String, dynamic>>.from(cab['cables'] ?? []);
    cables.removeWhere((c) => c['id'] == cableId);
    cab['cables'] = cables;
    final conn = List<Map<String, dynamic>>.from(cab['connections'] ?? []);
    conn.removeWhere((c) => c['cable1'] == cableId || c['cable2'] == cableId);
    cab['connections'] = conn;
    _touchCabinet(cab);
    if (_selectedCableId == cableId) _selectedCableId = null;
    await _persist();
    setState(() {});
  }

  Future<void> _editCableName(int cableId) async {
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return;
    final ctrl = TextEditingController(text: cable['name'] ?? '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать имя кабеля'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              cable['name'] = ctrl.text.trim();
              if (_selectedCabinet != null) _touchCabinet(_selectedCabinet!);
              await _persist();
              setState(() {});
              Navigator.of(context).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCableSide(int cableId) async {
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return;
    final cur = (cable['side'] as int?) ?? 0;
    cable['side'] = cur == 0 ? 1 : 0;
    if (_selectedCabinet != null) _touchCabinet(_selectedCabinet!);
    await _persist();
    setState(() {});
  }

  Future<void> _editFiber(int cableId, int fiberIndex) async {
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) return;
    final comments = List<String>.from(cable['fiber_comments'] ?? []);
    final spliters = List<int>.from(cable['spliters'] ?? []);
    if (fiberIndex >= comments.length || fiberIndex >= spliters.length) return;
    final ctrl = TextEditingController(text: comments[fiberIndex]);
    int spliter = spliters[fiberIndex];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Кабель: ${cable['name']} | Волокно ${fiberIndex + 1}'),
              const SizedBox(height: 12),
              TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Комментарий')),
              Row(
                children: [
                  const Text('Сплиттер:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: spliter,
                    items: [0, 2, 4, 8, 16, 32].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? 'Нет' : '$v'))).toList(),
                    onChanged: (v) => setSheet(() => spliter = v ?? 0),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      comments[fiberIndex] = ctrl.text.trim();
                      spliters[fiberIndex] = spliter;
                      cable['fiber_comments'] = comments;
                      cable['spliters'] = spliters;
                      if (_selectedCabinet != null) _touchCabinet(_selectedCabinet!);
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
        ),
      ),
    );
  }

  bool _fiberHasSpliter(int cableId, int fiberIndex) {
    final c = _getCableById(cableId);
    if (c == null) return false;
    final s = List<int>.from(c['spliters'] ?? []);
    return fiberIndex < s.length && s[fiberIndex] > 0;
  }

  bool _isFiberBusy(List<Map<String, dynamic>> connections, int cableId, int fiberIndex) {
    if (_fiberHasSpliter(cableId, fiberIndex)) return false;
    return connections.any((c) {
      final c1 = c['cable1'], f1 = c['fiber1'], c2 = c['cable2'], f2 = c['fiber2'];
      return (c1 == cableId && f1 == fiberIndex) || (c2 == cableId && f2 == fiberIndex);
    });
  }

  bool _isPortBusy(List<Map<String, dynamic>> connections, int switchId, int portIndex) {
    return connections.any((c) {
      final s1 = c['switch1'], p1 = c['port1'], s2 = c['switch2'], p2 = c['port2'];
      return (s1 == switchId && p1 == portIndex) || (s2 == switchId && p2 == portIndex);
    });
  }

  String _endpointKey(Map<String, dynamic> c, bool first) {
    if (first && c['cable1'] != null && c['fiber1'] != null) return 'f${c['cable1']}:${c['fiber1']}';
    if (first && c['switch1'] != null && c['port1'] != null) return 'p${c['switch1']}:${c['port1']}';
    if (!first && c['cable2'] != null && c['fiber2'] != null) return 'f${c['cable2']}:${c['fiber2']}';
    if (!first && c['switch2'] != null && c['port2'] != null) return 'p${c['switch2']}:${c['port2']}';
    return '';
  }

  bool _connectionExists(List<Map<String, dynamic>> connections, Map<String, dynamic> conn) {
    final a = _endpointKey(conn, true);
    final b = _endpointKey(conn, false);
    if (a.isEmpty || b.isEmpty) return false;
    return connections.any((c) {
      final x = _endpointKey(c, true);
      final y = _endpointKey(c, false);
      return (a == x && b == y) || (a == y && b == x);
    });
  }

  bool _isEndpointBusy(List<Map<String, dynamic>> conn, Map<String, dynamic> end) {
    if (end['cableId'] != null && end['fiberIndex'] != null) {
      return _isFiberBusy(conn, end['cableId'] as int, end['fiberIndex'] as int);
    }
    if (end['switchId'] != null && end['portIndex'] != null) {
      return _isPortBusy(conn, end['switchId'] as int, end['portIndex'] as int);
    }
    return false;
  }

  Future<void> _addConnectionUnified(Map<String, dynamic> conn) async {
    final selected = _selectedCabinet;
    if (selected == null) return;
    final idx = _cabinetStore.indexWhere((c) => c['id'] == selected['id']);
    final cab = idx >= 0 ? _cabinetStore[idx] : selected;
    final connList = List<Map<String, dynamic>>.from(cab['connections'] ?? []);

    final end1 = conn['cable1'] != null ? {'cableId': conn['cable1'], 'fiberIndex': conn['fiber1']} : {'switchId': conn['switch1'], 'portIndex': conn['port1']};
    final end2 = conn['cable2'] != null ? {'cableId': conn['cable2'], 'fiberIndex': conn['fiber2']} : {'switchId': conn['switch2'], 'portIndex': conn['port2']};

    if (end1['cableId'] != null && end2['cableId'] != null && end1['cableId'] == end2['cableId']) {
      _showSnack('Нельзя соединять волокна одного кабеля');
      return;
    }
    if (end1['switchId'] != null && end2['switchId'] != null && end1['switchId'] == end2['switchId']) {
      _showSnack('Нельзя соединять порты одного коммутатора');
      return;
    }
    if (_isEndpointBusy(connList, end1) || _isEndpointBusy(connList, end2)) {
      _showSnack('Конечная точка уже используется');
      return;
    }
    if (_connectionExists(connList, conn)) {
      _showSnack('Такое соединение уже есть');
      return;
    }
    connList.add(Map<String, dynamic>.from(conn));
    cab['connections'] = connList;
    _touchCabinet(cab);
    if (idx >= 0) _selectedCabinet = cab;
    await _persist();
    setState(() {});
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _statusDot(bool dirty) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: dirty ? Colors.red : Colors.green, shape: BoxShape.circle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDirty = _cabinetStore.any((c) => c['deleted'] != true && c['dirty'] == true);
    return Scaffold(
      appBar: AppBar(
        title: Text('Сетевые шкафы v$_version'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _mapView = !_mapView),
            icon: Icon(_mapView ? Icons.list : Icons.map),
            tooltip: _mapView ? 'Список' : 'Карта',
          ),
          IconButton(
            onPressed: _syncing ? null : _syncAll,
            icon: Icon(Icons.cloud_upload, color: hasDirty ? Colors.red : Colors.green),
            tooltip: 'Синхронизировать',
          ),
          IconButton(onPressed: _showCabinetEditor, icon: const Icon(Icons.add), tooltip: 'Новый шкаф'),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          if (_mapView) return _buildMapPane();
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                SizedBox(width: 320, child: _buildListPane()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildDetailPane()),
              ],
            );
          }
          return _selectedCabinet == null ? _buildListPane() : _buildDetailPane(showBack: true);
        },
      ),
    );
  }

  Widget _buildMapPane() {
    final withCoords = _cabinets.where((c) => c['location_lat'] != null && c['location_lng'] != null).toList();
    final center = withCoords.isNotEmpty
        ? LatLng(withCoords.first['location_lat'] as double, withCoords.first['location_lng'] as double)
        : const LatLng(55.751244, 37.618423);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        center: center,
        zoom: _mapZoom,
        maxZoom: 19,
        onPositionChanged: (pos, _) { if (pos.zoom != null) _mapZoom = pos.zoom!; },
      ),
      children: [
        yandexMapTileLayer,
        MarkerLayer(
          markers: withCoords.map((cab) {
            final p = LatLng(cab['location_lat'] as double, cab['location_lng'] as double);
            return Marker(
              point: p,
              width: 40,
              height: 40,
              builder: (ctx) => GestureDetector(
                onTap: () => _showCabinetFromMap(cab),
                child: const Icon(Icons.dns, color: Colors.blue, size: 32),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showCabinetFromMap(Map<String, dynamic> cab) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cab['name'] ?? 'Без названия', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(cab['location'] ?? ''),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() { _selectedCabinet = cab; _mapView = false; });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Открыть'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListPane() {
    if (_loadingCabinets) return const Center(child: CircularProgressIndicator());
    if (_cabinets.isEmpty) return const Center(child: Text('Шкафов пока нет. Добавьте первую запись.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _cabinets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final cab = _cabinets[i];
        final sel = _selectedCabinet?['id'] == cab['id'];
        return Card(
          color: sel ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            leading: _statusDot(cab['dirty'] == true),
            title: Text(cab['name'] ?? 'Без названия'),
            subtitle: Text(cab['location'] ?? ''),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _showCabinetEditor(cabinet: cab);
                if (v == 'geo') _openCabinetLocation(cab);
                if (v == 'delete') _deleteCabinet(cab);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                PopupMenuItem(value: 'geo', child: Text('Геопозиция')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
            onTap: () => _selectCabinet(cab),
          ),
        );
      },
    );
  }

  Widget _buildDetailPane({bool showBack = false}) {
    if (_selectedCabinet == null) {
      return const Center(child: Text('Выберите шкаф слева'));
    }
    final cab = _selectedCabinet!;
    final connections = List<Map<String, dynamic>>.from(cab['connections'] ?? []);
    final switches = List<Map<String, dynamic>>.from(cab['switches'] ?? []);
    _currentFiberKeys.clear();
    _fiberColorByKey.clear();
    _fiberSideByKey.clear();
    _scheduleFiberLayout();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBack)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectedCabinet = null),
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
                        _statusDot(cab['dirty'] == true),
                        const SizedBox(width: 8),
                        Expanded(child: Text(cab['name'] ?? 'Без названия', style: Theme.of(context).textTheme.titleMedium)),
                        IconButton(
                          tooltip: 'Геопозиция',
                          onPressed: () => _openCabinetLocation(cab),
                          icon: const Icon(Icons.map),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(cab['location'] ?? ''),
                    if ((cab['comment'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 8), Text(cab['comment'])],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Коммутаторы', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(onPressed: _addSwitch, icon: const Icon(Icons.add), label: const Text('Добавить')),
              ],
            ),
          ),
          if (switches.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Нет коммутаторов')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Кабели', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(onPressed: _addCable, icon: const Icon(Icons.add), label: const Text('Добавить кабель')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  child: Stack(
                    key: _fiberAreaKey,
                    alignment: Alignment.topLeft,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (switches.isNotEmpty) ...[
                            ...switches.map((s) => _buildSwitchRow(s)),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildCableColumn(0)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildCableColumn(1)),
                            ],
                          ),
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
                );
              },
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
                if (connections.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      cab['connections'] = <Map<String, dynamic>>[];
                      _touchCabinet(cab);
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
            const Padding(padding: EdgeInsets.all(12), child: Text('Соединений пока нет'))
          else
            Column(
              children: connections.map((c) {
                String left = '';
                if (c['cable1'] != null && c['fiber1'] != null) {
                  final cx = _getCableById(c['cable1']);
                  left = '${cx?['name'] ?? 'Кабель'}[${(c['fiber1'] as int) + 1}]';
                } else if (c['switch1'] != null && c['port1'] != null) {
                  final sx = _getSwitchById(c['switch1']);
                  left = '${sx?['name'] ?? 'Свитч'} порт ${(c['port1'] as int) + 1}';
                }
                String right = '';
                if (c['cable2'] != null && c['fiber2'] != null) {
                  final cx = _getCableById(c['cable2']);
                  right = '${cx?['name'] ?? 'Кабель'}[${(c['fiber2'] as int) + 1}]';
                } else if (c['switch2'] != null && c['port2'] != null) {
                  final sx = _getSwitchById(c['switch2']);
                  right = '${sx?['name'] ?? 'Свитч'} порт ${(c['port2'] as int) + 1}';
                }
                return ListTile(
                  dense: true,
                  leading: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      connections.remove(c);
                      cab['connections'] = connections;
                      _touchCabinet(cab);
                      await _persist();
                      setState(() {});
                    },
                  ),
                  title: Text('$left <--> $right'),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(Map<String, dynamic> sw) {
    final portsCount = (sw['ports'] as int?) ?? 24;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${sw['name'] ?? 'Свитч'} ${sw['model']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) { if (v == 'delete') _deleteSwitch(sw['id']); },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Удалить'))],
                ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(portsCount, (i) {
                final keyId = _portKey(sw['id'], i);
                _currentFiberKeys.add(keyId);
                _fiberColorByKey[keyId] = Colors.grey;
                _fiberSideByKey[keyId] = 0;
                final anchorKey = _fiberKeys.putIfAbsent(keyId, () => GlobalKey());
                final portWidget = DragTarget<Map<String, dynamic>>(
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (d) {
                    final m = d.data;
                    Map<String, dynamic> conn;
                    if (m['cableId'] != null) {
                      conn = {'cable1': m['cableId'], 'fiber1': m['fiberIndex'], 'switch2': sw['id'], 'port2': i};
                    } else {
                      conn = {'switch1': m['switchId'], 'port1': m['portIndex'], 'switch2': sw['id'], 'port2': i};
                    }
                    _addConnectionUnified(conn);
                  },
                  builder: (ctx, cand, rej) {
                    final hover = cand.isNotEmpty;
                    return Draggable<Map<String, dynamic>>(
                      data: {'switchId': sw['id'], 'portIndex': i},
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 10))),
                        ),
                      ),
                      childWhenDragging: Opacity(opacity: 0.3, child: _portSquare(i + 1, hover)),
                      child: _portSquare(i + 1, hover, key: anchorKey),
                    );
                  },
                );
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: portWidget,
                );
              }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _portSquare(int label, bool highlight, {Key? key}) {
    return Container(
      key: key,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: highlight ? Colors.deepOrange : Colors.black54, width: highlight ? 2 : 1),
        boxShadow: highlight ? [BoxShadow(color: Colors.deepOrange.withValues(alpha: 0.5), blurRadius: 4)] : null,
      ),
      child: Center(child: Text('$label', style: const TextStyle(fontSize: 10))),
    );
  }

  Widget _buildCableColumn(int side) {
    final cables = _getCablesBySide(side);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(side == 0 ? 'Слева' : 'Справа', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (cables.isEmpty) const Text('Нет кабелей'),
        ...cables.map((cable) {
          final sel = _selectedCableId == cable['id'];
          return Card(
            color: sel ? Theme.of(context).colorScheme.primaryContainer : null,
            child: InkWell(
              onTap: () => setState(() => _selectedCableId = cable['id']),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(cable['name'] ?? 'Кабель', style: const TextStyle(fontWeight: FontWeight.bold))),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') _editCableName(cable['id']);
                            if (v == 'swap') _toggleCableSide(cable['id']);
                            if (v == 'delete') _deleteCable(cable['id']);
                          },
                          itemBuilder: (_) => const [
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
                        final anchorKey = _fiberKeys.putIfAbsent(keyId, () => GlobalKey());
                        final fiberWidget = DragTarget<Map<String, dynamic>>(
                          onWillAcceptWithDetails: (_) => true,
                          onAcceptWithDetails: (d) {
                            final m = d.data;
                            Map<String, dynamic> conn;
                            if (m['cableId'] != null) {
                              conn = {'cable1': m['cableId'], 'fiber1': m['fiberIndex'], 'cable2': cable['id'], 'fiber2': i};
                            } else {
                              conn = {'switch1': m['switchId'], 'port1': m['portIndex'], 'cable2': cable['id'], 'fiber2': i};
                            }
                            _addConnectionUnified(conn);
                          },
                          builder: (ctx, cand, rej) {
                            final hover = cand.isNotEmpty;
                            return Draggable<Map<String, dynamic>>(
                              data: {'cableId': cable['id'], 'fiberIndex': i},
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
                                    child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: color == Colors.black ? Colors.white : Colors.black)),
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(opacity: 0.3, child: _fiberCircle(color, i + 1, hover)),
                              child: GestureDetector(
                                onTap: () => _editFiber(cable['id'], i),
                                child: _fiberCircle(color, i + 1, hover, key: spliter > 0 ? null : anchorKey),
                              ),
                            );
                          },
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (side == 1 && spliter > 0) _spliterBadge(spliter, key: anchorKey),
                              if (side == 1 && spliter > 0) const SizedBox(width: 6),
                              fiberWidget,
                              if (side == 0 && spliter > 0) const SizedBox(width: 6),
                              if (side == 0 && spliter > 0) _spliterBadge(spliter, key: anchorKey),
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
    return Container(
      key: key,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: highlight ? Colors.deepOrange : Colors.black, width: highlight ? 2 : 1),
        boxShadow: highlight ? [BoxShadow(color: Colors.deepOrange.withValues(alpha: 0.5), blurRadius: 6)] : null,
      ),
      child: Center(
        child: Text('$label', style: TextStyle(fontSize: 11, color: color == Colors.black ? Colors.white : Colors.black)),
      ),
    );
  }

  Widget _spliterBadge(int spliter, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
      child: Text('1:$spliter', style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }

  Widget _buildSelectedCableDetails() {
    final cable = _getCableById(_selectedCableId!);
    if (cable == null || cable.isEmpty) return const SizedBox.shrink();
    final comments = List<String>.from(cable['fiber_comments'] ?? []);
    final spliters = List<int>.from(cable['spliters'] ?? []);
    final commentItems = comments.asMap().entries.where((e) => e.value.trim().isNotEmpty).map((e) => Row(children: [Text('[${e.key + 1}]: '), Text(e.value)])).toList();
    final spliterItems = spliters.asMap().entries.where((e) => e.value != 0).map((e) => Row(children: [Text('[${e.key + 1}]: '), Text('Сплиттер ${e.value}')])).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Кабель: ${cable['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (commentItems.isNotEmpty) ...[const SizedBox(height: 6), const Text('Комментарии по волокнам:'), ...commentItems],
          if (spliterItems.isNotEmpty) ...[const SizedBox(height: 6), const Text('Сплиттеры:'), ...spliterItems],
        ],
      ),
    );
  }
}

class _ConnectionsPainter extends CustomPainter {
  final List<Map<String, dynamic>> connections;
  final Map<String, Offset> positions;
  final Map<String, Color> colors;

  _ConnectionsPainter({required this.connections, required this.positions, required this.colors});

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';
  String _portKey(int switchId, int portIndex) => 's$switchId:$portIndex';

  Offset? _getPos(Map<String, dynamic> conn, bool first) {
    String k;
    if (first) {
      if (conn['cable1'] != null && conn['fiber1'] != null) {
        k = _fiberKey(conn['cable1'] as int, conn['fiber1'] as int);
      } else if (conn['switch1'] != null && conn['port1'] != null) {
        k = _portKey(conn['switch1'] as int, conn['port1'] as int);
      } else {
        return null;
      }
    } else {
      if (conn['cable2'] != null && conn['fiber2'] != null) {
        k = _fiberKey(conn['cable2'] as int, conn['fiber2'] as int);
      } else if (conn['switch2'] != null && conn['port2'] != null) {
        k = _portKey(conn['switch2'] as int, conn['port2'] as int);
      } else {
        return null;
      }
    }
    return positions[k];
  }

  Color _getColor(Map<String, dynamic> conn, bool first) {
    if (first && conn['cable1'] != null && conn['fiber1'] != null) {
      final k = _fiberKey(conn['cable1'] as int, conn['fiber1'] as int);
      return colors[k] ?? Colors.deepOrange;
    }
    if (!first && conn['cable2'] != null && conn['fiber2'] != null) {
      final k = _fiberKey(conn['cable2'] as int, conn['fiber2'] as int);
      return colors[k] ?? Colors.deepOrange;
    }
    return Colors.grey;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    for (final conn in connections) {
      final p1 = _getPos(conn, true);
      final p2 = _getPos(conn, false);
      if (p1 == null || p2 == null) continue;
      paint.color = _getColor(conn, true).withValues(alpha: 0.75);
      final midX = (p1.dx + p2.dx) / 2;
      final path = Path()..moveTo(p1.dx, p1.dy)..cubicTo(midX, p1.dy, midX, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
      final dotPaint = Paint()..color = paint.color;
      canvas.drawCircle(p1, 3, dotPaint);
      canvas.drawCircle(p2, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter old) =>
      old.connections != connections || old.positions != positions || old.colors != colors;
}
