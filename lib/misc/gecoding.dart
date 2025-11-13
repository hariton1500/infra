import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:universal_html/html.dart' as html;

import 'package:latlong2/latlong.dart';

Future<LatLng?>? getGeoCoding(String address, {String? source}) async {
  print(address);
  if (address.isEmpty) return null;
  try {
    String reqText = '';
    switch (source) {
      case 'yandex':
        String key = dotenv.env['yandexkey3']!;
        reqText = 'https://geocode-maps.yandex.ru/v1/?apikey=$key&geocode=$address&format=json';
        break;
      case 'osm':
        reqText = 'https://nominatim.openstreetmap.org/search?q=$address&format=json';
      default:
    }
    print('make get request to:\n$reqText');
    final request = await html.HttpRequest.request(
      reqText,
      method: 'GET',
      withCredentials: true,
    );
    print('request:\n${request.responseText}');
    final data = jsonDecode(request.responseText!) as Map<String, dynamic>;
    print('decoded result:\n$data');
    return data['response']['featureMember'][0]['GeoObject']['Point']['Pos'];
  } catch (e) {
    print('error:');
    print(e);
    return null;
  }
}