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
  Pillar.fromMap(Map<String, dynamic> map)
    : super(id: map['id'], lat: map['lat'], long: map['long']);

  Future<List<Map<String, dynamic>>> updatePillarPoint({
    required LatLng newPoint,
  }) async {
    print('change point of pillar[id = $id, lat = $lat, long = $long]');
    var res =
        await sbPillars
            .update({'lat': newPoint.latitude, 'long': newPoint.longitude})
            .eq('id', id!)
            .select();
    return res;
  }

  Marker marker(double zoom, Widget child) {
    return Marker(
      point: LatLng(lat!, long!),
      width: zoom / 3,
      height: zoom / 3,
      builder: (context) => child,
    );
  }

  Widget pillarWidget(double zoom) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black),
      color: Colors.amber,
    ),
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
  int? fibersNumber;
  List<LatLng>? points;
  String? comment;
  Cable({this.id, this.fibersNumber, this.points});

  Cable.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    fibersNumber = map['fibers_number'];
    comment = map['comment'];
    points = List<LatLng>.from(
      (map['points'] as List).map((e) => LatLng.fromJson(e)).toList(),
    );
  }

  bool isInRadius({required LatLng toPoint, required int radius}) {
    final distance = Distance();
    return points!.any((p) => distance(toPoint, p) <= radius);
  }

  Future<List<Map<String, dynamic>>> updateCableHistory({
    required Map<String, dynamic> before
  }) async {
    return sbHistory.insert({
      'cable_id': id,
      'before': before,
      'after': toMap(),
      'by_name': activeUser['login'],
      //'comment': comment,
    }).select();
  }

  Future<List<Map<String, dynamic>>> markAsDeleted() async {
    return await sbCables.update({'deleted': true}).eq('id', id!).select();
  }

  Future<List<Map<String, dynamic>>> storeNewCable() async {
    return await sbCables.insert({
      'fibers_number': fibersNumber,
      'points': (points),
      'created_by': activeUser['login'],
    }).select();
  }

  Future<List<Map<String, dynamic>>>storeCable(Cable? cable) async {
    if (cable == null) {
      return storeNewCable();
    } else {
      return await sbCables.update({
        'fibers_number': fibersNumber,
        'points': (points),
        'created_by': activeUser['login'],
      }).eq('id', id!).select();
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'fibers_number': fibersNumber,
    'points': points,
    'comment': comment,
  };

  int cableLength() {
    if (points == null) return 0;
    int sum = 0;
    for (int i = 1; i < points!.length; i++) {
      sum += Distance().distance(points![i - 1], points![i]).toInt();
    }
    return sum;
  }

  @override
  String toString() =>
      'Cable[id = $id\nfibersNumber = $fibersNumber\npoints = $points\ncomment = $comment]';

}
