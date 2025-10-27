import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  "Arto_Black"
];

Map<String, dynamic> activeUser = {};

List<String> statuses = ['Внимание', 'Нормально', 'Важно', 'Отложен', 'Завершен'];
List<Color> statusColors = [Colors.red, Colors.green, Colors.yellow, Colors.redAccent, Colors.green];

List<Map<String, dynamic>> ponBoxes = [];
var sb = Supabase.instance.client.from('PON_boxes');

Future loadBoxes() async {
  var res = await sb.select();
  ponBoxes = res;
  print('loaded ${res.length} objects');
}