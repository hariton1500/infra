import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:infra/Pages/error.dart';
import 'package:infra/Pages/home.dart';
import 'package:infra/globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "secrets.env");
  await Supabase.initialize(
    url: dotenv.env['url']!,
    anonKey: dotenv.env['anon']!,
  );
  //String cookies = html.document.cookie ?? "";
  //print('cookies:\n$cookies');
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
    runApp(const MyApp());
  } catch (e) {
    print('Error:\n$e');
    //runApp(const ErrorApp());
    activeUser = {'login': 'hariton', 'level': 0};
    runApp(MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Инфраструктура PON',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});


  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
