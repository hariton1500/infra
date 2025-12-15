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

Map<int, Color> fibers = {
  1 : Colors.grey,
  2 : Colors.blue,
  4 : Colors.green,
  8 : Colors.yellow,
  12 : Colors.red,
  16 : Colors.pink,
  20 : Colors.black,
  24 : Colors.black,
  32 : Colors.black,
  36 : Colors.black,
  48 : Colors.black,
  64 : Colors.black,
  96 : Colors.black,
};

Map<String, dynamic> activeUser = {};

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
