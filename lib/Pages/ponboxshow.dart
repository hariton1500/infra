import 'package:flutter/material.dart';
import 'package:infra/globals.dart';
import 'package:infra/Pages/ponboxedit.dart';
import 'package:infra/Pages/historyshow.dart';
import 'package:latlong2/latlong.dart';

/// Форматирование даты в формат день.месяц.год
String formatDateDMY(dynamic value) {
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

/// Виджет для отображения информации о PON боксе
class PonBoxInfoWidget extends StatelessWidget {
  final Map<String, dynamic> ponBox;
  final VoidCallback? onEdit;
  final VoidCallback? onSelect;
  final bool showSelectButton;

  const PonBoxInfoWidget({
    super.key,
    required this.ponBox,
    this.onEdit,
    this.onSelect,
    this.showSelectButton = false,
  });

  @override
  Widget build(BuildContext context) {
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
                if (ponBox['has_divider'] == true && ponBox['divider_ports'] != null)
                  Chip(
                    avatar: const Icon(Icons.call_split, size: 18),
                    label: Text('Делитель: ${ponBox['divider_ports']}'),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (ponBox['has_divider'] == true && ponBox['divider_ports'] != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.call_split),
                title: Text('Первичный делитель на ${ponBox['divider_ports']} портов'),
              ),
            if (ponBox['has_divider'] == true && ponBox['divider_ports'] != null)
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
              title: Text('Создан: ${formatDateDMY(ponBox['created_at'])}'),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    showHistoryDialog(context, ponBox['id']);
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('История'),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    label: const Text('Редактировать'),
                  ),
                ],
                if (onEdit != null && showSelectButton)
                  const SizedBox(width: 8),
                if (showSelectButton && onSelect != null)
                  ElevatedButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(Icons.check),
                    label: const Text('Выбрать этот'),
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

/// Функция для отображения bottom sheet с информацией о PON боксе
void showPonBoxInfoSheet(
  BuildContext context,
  Map<String, dynamic> ponBox,
  void Function()? onUpdated, {
  LatLng? currentMapCenter,
}) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return PonBoxInfoWidget(
        ponBox: ponBox,
        onEdit: () {
          Navigator.of(context).pop();
          showEditPonBoxDialog(
            context,
            ponBox,
            () {
              if (onUpdated != null) onUpdated();
            },
            currentMapCenter: currentMapCenter,
          );
        },
        onSelect: params.containsKey('getponbox')
            ? () {
                print('Выбран пон бокс ${ponBox['id']}');
                //Navigator.of(context).pop(ponBox['id']);
              }
            : null,
        showSelectButton: params.containsKey('getponbox'),
      );
    },
  );
}

