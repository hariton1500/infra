import 'package:flutter/material.dart';
import 'package:infra/Pages/home.dart';
import 'package:infra/Pages/muff_notebook.dart';
import 'package:infra/Pages/network_cabinet.dart';
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
        minimum: const EdgeInsets.only(left: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('Карта PON боксов и кабелей'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const MuffNotebookPage()),
                );
              },
              icon: const Icon(Icons.notes),
              label: const Text('Блокнот муфт'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CabinetNotebookPage()),
                );
              },
              icon: const Icon(Icons.dns),
              label: const Text('Сетевые шкафы'),
            ),
          ],
        ),
      ),
    );
  }
}
