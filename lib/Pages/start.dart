import 'package:flutter/material.dart';
import 'package:infra/Pages/home.dart';
import 'package:infra/globals.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('user: ${activeUser['login'] ?? ''}'),
      ),
      body: SafeArea(
        minimum: EdgeInsets.only(left: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => HomePage()));
              },
              icon: Icon(Icons.map),
              label: Text('Карта PON боксов и кабелей')
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => HomePage()));
              },
              icon: Icon(Icons.map),
              label: Text('Личный блокнот с муфтами')
            )
          ],
        )
      ),
    );
  }
}