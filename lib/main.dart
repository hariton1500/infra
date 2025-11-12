import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:infra/Pages/error.dart';
import 'package:infra/Pages/home.dart';
import 'package:infra/globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
//import 'package:universal_html/parsing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "secrets.env");
  await Supabase.initialize(
    url: dotenv.env['url']!,
    anonKey: dotenv.env['anon']!,
  );
  try {
    final request = await html.HttpRequest.request(
      'https://billing.evpanet.com/admin/session_info.php',
      method: 'GET',
      withCredentials: true,
    );
    print('request:\n${request.responseText}');
    final data = jsonDecode(request.responseText!) as Map<String, dynamic>;
    print('decoded result:\n$data');
    activeUser = {
      'login': data['admin_login'].toString(),
      'level': int.parse(data['level']),
    };
    //get parameters
    print('get params');
    print(html.window.toString());
    print('loading info');
    await loadBoxes();
    runApp(const MyApp());
  } catch (e) {
    print('Error:\n$e');
    //runApp(const ErrorApp());
    activeUser = {'login': 'magistik', 'level': 10};
    //get parameters
    print('get params');
    print(html.window.location.href);
    print(params);
    print('loading info');
    await loadBoxes();
    runApp(MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Инфраструктура PON',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}
