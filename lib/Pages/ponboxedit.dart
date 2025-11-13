import 'package:flutter/material.dart';
import 'package:infra/globals.dart';
import 'package:latlong2/latlong.dart';

/// Диалог редактирования PON бокса
/// 
/// Позволяет редактировать:
/// - Координаты (широта и долгота)
/// - Количество портов
/// - Количество использованных портов
/// - Наличие первичного делителя
/// - Количество портов делителя
Future<void> showEditPonBoxDialog(
  BuildContext context,
  Map<String, dynamic> ponBox,
  void Function() onUpdated, {
  LatLng? currentMapCenter,
}) async {
  await showDialog<void>(
    context: context,
    builder: (editContext) {
      double editLat = (ponBox['lat'] ?? 0.0).toDouble();
      double editLong = (ponBox['long'] ?? 0.0).toDouble();
      int editPorts = ponBox['ports'] ?? 0;
      int editUsedPorts = ponBox['used_ports'] ?? 0;
      bool editHasDivider = ponBox['has_divider'] == true;
      int? editDividerPorts = ponBox['divider_ports'] != null ? ponBox['divider_ports'] as int : null;
      
      final latController = TextEditingController(text: editLat.toStringAsFixed(6));
      final longController = TextEditingController(text: editLong.toStringAsFixed(6));
      
      return Dialog(
        child: StatefulBuilder(
          builder: (context, setEditState) {
            return SizedBox(
              width: 400,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Редактировать PON бокс', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Координаты', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latController,
                              decoration: InputDecoration(
                                labelText: 'Широта',
                                hintText: '45.200051',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.north),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (value) {
                                final parsed = double.tryParse(value);
                                if (parsed != null) {
                                  editLat = parsed;
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: longController,
                              decoration: InputDecoration(
                                labelText: 'Долгота',
                                hintText: '33.357209',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.east),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (value) {
                                final parsed = double.tryParse(value);
                                if (parsed != null) {
                                  editLong = parsed;
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      if (currentMapCenter != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            latController.text = currentMapCenter.latitude.toStringAsFixed(6);
                            longController.text = currentMapCenter.longitude.toStringAsFixed(6);
                            setEditState(() {
                              editLat = currentMapCenter.latitude;
                              editLong = currentMapCenter.longitude;
                            });
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Использовать центр карты'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text('Количество портов', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final q in [2, 4, 8, 16]) ChoiceChip(
                            label: Text(q.toString()),
                            selected: editPorts == q,
                            onSelected: (_) {
                              setEditState(() {
                                editPorts = q;
                                if (editUsedPorts > editPorts) {
                                  editUsedPorts = editPorts;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Использованных портов', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Slider(
                        value: editUsedPorts.toDouble().clamp(0, editPorts.toDouble()),
                        min: 0,
                        max: editPorts > 0 ? editPorts.toDouble() : 16.0,
                        divisions: editPorts > 0 ? editPorts : 16,
                        label: '$editUsedPorts',
                        onChanged: (v) {
                          setEditState(() {
                            editUsedPorts = v.round();
                          });
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Выбрано: $editUsedPorts из $editPorts', style: Theme.of(context).textTheme.bodySmall),
                          if (editUsedPorts > editPorts) 
                            Text('Слишком много', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                              subtitle: editHasDivider && editDividerPorts != null 
                                  ? Text('На $editDividerPorts портов', style: Theme.of(context).textTheme.bodySmall) 
                                  : null,
                              value: editHasDivider,
                              onChanged: (value) {
                                setEditState(() {
                                  editHasDivider = value;
                                  if (!value) editDividerPorts = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      if (editHasDivider) ...[
                        const SizedBox(height: 8),
                        Text('Портов делителя', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final q in [2, 4, 8, 16]) ChoiceChip(
                              label: Text(q.toString()),
                              selected: editDividerPorts == q,
                              onSelected: (_) {
                                setEditState(() {
                                  editDividerPorts = editDividerPorts == q ? null : q;
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
                              Navigator.of(editContext).pop();
                            },
                            child: const Text('Отмена'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              var updateData = <String, dynamic>{
                                'lat': editLat,
                                'long': editLong,
                                'ports': editPorts,
                                'used_ports': editUsedPorts,
                              };
                              if (editHasDivider && editDividerPorts != null) {
                                updateData['has_divider'] = true;
                                updateData['divider_ports'] = editDividerPorts;
                              } else {
                                updateData['has_divider'] = false;
                                updateData['divider_ports'] = null;
                              }
                              try {
                                var historyData = {
                                  'ponbox_id': ponBox['id'],
                                  'by_name': activeUser['login'],
                                  'before': ponBox,
                                };
                                var res = await sb.update(updateData).eq('id', ponBox['id']).select();
                                if (res.isNotEmpty) {
                                  var index = ponBoxes.indexWhere((b) => b['id'] == ponBox['id']);
                                  if (index != -1) {
                                    ponBoxes[index] = res.first;
                                  }
                                  historyData['after'] = res.first;
                                  await history.insert(historyData).select();
                                  // ignore: use_build_context_synchronously
                                  Navigator.of(editContext).pop();
                                  // ignore: use_build_context_synchronously
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Изменения сохранены')),
                                  );
                                  onUpdated();
                                }
                              } catch (e) {
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Сохранить'),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

