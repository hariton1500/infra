import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

final httpClient = RetryClient(Client());

// TODO: This causes unneccessary rebuilding
TileLayer get openStreetMapTileLayer => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'dev.fleaflet.flutter_map.example',
      tileProvider: NetworkTileProvider(httpClient: httpClient),
    );

TileLayer get yandexMapTileLayer => TileLayer(
  //urlTemplate: 'https://core-sat.maps.yandex.net/tiles?l=map&x={x}&y={y}&z={z}&lang=ru_RU',
  urlTemplate: 'https://core-renderer-tiles.maps.yandex.net/tiles?l=map&x={x}&y={y}&z={z}&lang=ru_RU',
  tileProvider: NetworkTileProvider(httpClient: httpClient),
  
  subdomains: ['01', '02', '03', '04'],
);