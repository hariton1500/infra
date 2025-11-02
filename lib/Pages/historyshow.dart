import 'package:flutter/material.dart';
import 'package:infra/globals.dart';

/// Форматирование даты и времени в формат день.месяц.год час:минута
String formatDateDMYTime(dynamic value) {
  try {
    DateTime dt;
    if (value is DateTime) {
      dt = value.toLocal();
    } else {
      dt = DateTime.parse(value.toString()).toLocal();
    }
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  } catch (_) {
    return value?.toString() ?? '';
  }
}

/// Загрузка истории изменений для конкретного PON бокса
Future<List<Map<String, dynamic>>> loadBoxHistory(int boxId) async {
  try {
    var res = await history
        .select()
        .eq('ponbox_id', boxId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  } catch (e) {
    print('Ошибка загрузки истории: $e');
    return [];
  }
}

/// Получение иконки для типа изменения
Icon _getHistoryIcon(String? action, BuildContext context) {
  switch (action) {
    case 'create':
      return Icon(Icons.add_circle, color: Colors.green, size: 24);
    case 'update':
      return Icon(Icons.edit, color: Theme.of(context).colorScheme.primary, size: 24);
    case 'delete':
      return Icon(Icons.delete, color: Colors.red, size: 24);
    default:
      return Icon(Icons.info, color: Colors.grey, size: 24);
  }
}

/// Форматирование изменений для отображения
String _formatChanges(Map<String, dynamic>? before, Map<String, dynamic>? after) {
  if (before == null && after == null) return '';
  if (before == null) return 'Создан';
  if (after == null) return 'Удалён';
  
  List<String> changes = [];
  final fields = ['lat', 'long', 'ports', 'used_ports', 'has_divider', 'divider_ports'];
  
  for (var field in fields) {
    final oldVal = before[field];
    final newVal = after[field];
    
    if (oldVal != newVal) {
      String fieldName = _getFieldName(field);
      if (field == 'lat' || field == 'long') {
        final oldStr = oldVal != null ? (oldVal as num).toStringAsFixed(6) : '—';
        final newStr = newVal != null ? (newVal as num).toStringAsFixed(6) : '—';
        changes.add('$fieldName: $oldStr → $newStr');
      } else {
        changes.add('$fieldName: ${oldVal ?? '—'} → ${newVal ?? '—'}');
      }
    }
  }
  
  return changes.isEmpty ? 'Нет изменений' : changes.join('\n');
}

/// Получение читаемого названия поля
String _getFieldName(String field) {
  final Map<String, String> fieldNames = {
    'lat': 'Широта',
    'long': 'Долгота',
    'ports': 'Портов',
    'used_ports': 'Использовано',
    'has_divider': 'Первичный делитель',
    'divider_ports': 'Портов делителя',
  };
  return fieldNames[field] ?? field;
}

/// Виджет для отображения одной записи истории
class HistoryEntryWidget extends StatelessWidget {
  final Map<String, dynamic> entry;

  const HistoryEntryWidget({
    super.key,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final before = entry['before'] as Map<String, dynamic>?;
    final after = entry['after'] as Map<String, dynamic>?;
    final action = entry['action'] as String?;
    final byName = entry['by_name'] as String? ?? 'unknown';
    final createdAt = entry['created_at'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: _getHistoryIcon(action, context),
        title: Text(
          _formatChanges(before, after),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  byName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  formatDateDMYTime(createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Диалог для просмотра истории изменений PON бокса
Future<void> showHistoryDialog(
  BuildContext context,
  int boxId,
) async {
  // Показываем индикатор загрузки
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  // Загружаем историю
  final historyList = await loadBoxHistory(boxId);

  // Закрываем индикатор загрузки
  if (context.mounted) {
    Navigator.of(context).pop();
  }

  // Показываем диалог с историей
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (historyContext) {
        return Dialog(
          child: SizedBox(
            width: 600,
            height: 700,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('История изменений', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(historyContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: historyList.isEmpty
                      ? Center(
                          child: Text(
                            'История изменений пуста',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: historyList.length,
                          itemBuilder: (context, index) {
                            return HistoryEntryWidget(entry: historyList[index]);
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextButton(
                    onPressed: () => Navigator.of(historyContext).pop(),
                    child: const Text('Закрыть'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

