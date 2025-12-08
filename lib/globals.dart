import 'package:flutter/material.dart';
import 'package:infra/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

List<String> users = [
  "hariton",
  "serg",
  "opium",
  "maijor",
  "magistik",
  "rumit",
  "drybones",
  "kasper",
  "artem",
  "Lemon4ik",
  "taxist",
  "ldos",
  "Art85",
  "jeka",
  "Alex",
  "Nikey",
  "Masters",
  "sany7676",
  "Arto_Black",
];

Map<String, dynamic> activeUser = {};

List<String> statuses = [
  'Внимание',
  'Нормально',
  'Важно',
  'Отложен',
  'Завершен',
];
List<Color> statusColors = [
  Colors.red,
  Colors.green,
  Colors.yellow,
  Colors.redAccent,
  Colors.green,
];

List<Map<String, dynamic>> ponBoxes = [];
var sb = Supabase.instance.client.from('PON_boxes');
var sbHistory = Supabase.instance.client.from('change_history');
var sbPillars = Supabase.instance.client.from('Pillars');
var sbCables = Supabase.instance.client.from('Cables');

Future loadBoxes() async {
  var res = await sb.select();
  ponBoxes = res;
  print('loaded ${res.length} boxes');
}

List<Map<String, dynamic>> pillars = [];
Future loadPillars({bool? all}) async {
  var res = await sbPillars.select();
  pillars =
      (all != null && all) ? res : res.where((p) => !p['deleted']).toList();
  print('Loaded ${res.length} pillars');
}

List<Cable> cables = [];
Future loadCables({bool? all}) async {
  var res = await sbCables.select();
  var cablesMap =
      (all != null && all) ? res : res.where((p) => !p['deleted']).toList();
  cables = cablesMap.map((c) => Cable.fromMap(c)).toList();
  print('Loaded ${cables.length} cables');
}

var uri = Uri.dataFromString(html.window.location.href);
Map<String, String> params = uri.queryParameters;
