
abstract class Entity {
  int? id;
  double? lat, long;
  Entity({required this.lat, required this.long});
}

class Pillar extends Entity {
  Pillar({required super.lat, required super.long});
}


class PonBox extends Entity {
  PonBox({required super.lat, required super.long});
}