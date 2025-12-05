
import 'package:infra/globals.dart';
import 'package:latlong2/latlong.dart';

abstract class Entity {
  int? id;
  double? lat, long;
  Entity({required this.id, required this.lat, required this.long});
}

class Pillar extends Entity {
  Pillar({required super.id, required super.lat, required super.long});
  Pillar.fromMap(Map<String, dynamic> map) : super(id: map['id'], lat: map['lat'], long: map['long']);

  Future<List<Map<String, dynamic>>> updatePillarPoint({required LatLng newPoint}) async {
    print('change point of pillar[id = $id, lat = $lat, long = $long]');
    var res = await sbPillars.update({'lat': newPoint.latitude, 'long': newPoint.longitude}).eq('id', id!).select();
    return res;
  }
}


class PonBox extends Entity {
  PonBox({required super.id, required super.lat, required super.long});
}