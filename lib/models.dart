
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:infra/globals.dart';
import 'package:latlong2/latlong.dart';

abstract class Entity {
  int? id;
  double? lat, long;
  Entity({required this.id, this.lat, this.long});
}

class Pillar extends Entity {
  Pillar({required super.id, super.lat, super.long});
  Pillar.fromMap(Map<String, dynamic> map) : super(id: map['id'], lat: map['lat'], long: map['long']);

  Future<List<Map<String, dynamic>>> updatePillarPoint({required LatLng newPoint}) async {
    print('change point of pillar[id = $id, lat = $lat, long = $long]');
    var res = await sbPillars.update({'lat': newPoint.latitude, 'long': newPoint.longitude}).eq('id', id!).select();
    return res;
  }
  Marker marker(double zoom, Widget child) {
    return Marker(
      point: LatLng(lat!, long!),
      width: zoom / 3,
      height: zoom / 3,
      builder: (context) => child);
  }

 
  Widget pillarWidget(double zoom) => Container(
    decoration: BoxDecoration(border: Border.all(color: Colors.black), color: Colors.amber),
  );
  
  Future<List<Map<String, dynamic>>> markAsDeleted() {
    print('mark pillar[id = $id] as deleted');
    return sbPillars.update({'deleted': true}).eq('id', id!).select();
  }

  @override
  String toString() => 'Pillar[id = $id, lat = $lat, long = $long]';
}


class PonBox extends Entity {
  PonBox({required super.id, required super.lat, required super.long});
}

class Cable {
  int? id;
  int? fiberNumber;
  List<LatLng>? points;
  Cable({this.id, this.fiberNumber, this.points});

  Cable.fromMap(Map<String, dynamic> map) : id = map['id'], fiberNumber = map['fiberNumber'], points = map['points'];

  @override
  String toString() => 'Cable[id = $id, fiberNumber = $fiberNumber, points = $points]';
}