import 'package:flutter/material.dart';

Widget ponBoxWidget(Map<String, dynamic> box, double zoom) {
  //return Image.asset('pics/ponbox.png');
  return Stack(
    children: [
      Positioned(
        child: Image.asset('pics/ponbox.png'),
      ),
      Positioned(
        child: Align(alignment: Alignment.topRight, widthFactor: 1.5, child: Text(box['ports'].toString(), style: TextStyle(fontSize: zoom * 0.7, color: Colors.red, fontWeight: FontWeight.bold),))
      )
    ]
  );
}

Widget linkText(String text) {
  return Text('[ $text ]', style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Colors.blue),);
}