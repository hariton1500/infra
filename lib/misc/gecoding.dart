import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:universal_html/html.dart' as html;

import 'package:latlong2/latlong.dart';

Future<LatLng?>? getGeoCoding(String address) async {
  print(address);
  if (address.isEmpty) return null;
  try {
    String key = dotenv.env['yandexkey3']!;
    final request = await html.HttpRequest.request(
      'https://geocode-maps.yandex.ru/v1/?apikey=$key&geocode=$address&format=json',
      method: 'GET',
      withCredentials: true,
      onProgress: (progressEvent) => print(progressEvent.type),
    );
    print('request:\n${request.responseText}');
    final data = jsonDecode(request.responseText!) as Map<String, dynamic>;
    print('decoded result:\n$data');
    return data['response']['featureMember'][0]['GeoObject']['Point']['Pos'];
  } catch (e) {
    print('error:');
    print((e as html.ProgressEvent).type);
    return null;
  }
}