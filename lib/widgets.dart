import 'package:flutter/material.dart';

Widget ponBoxWidget(Map<String, dynamic> box, double zoom) {
  //return Image.asset('pics/ponbox.png');
  return Stack(
    children: [
      Positioned(
        child: Image.asset('pics/ponbox.png'),
      ),
      Positioned(
        child: Align(widthFactor: 1.5, child: Text(box['ports'].toString()))
      )
    ]
  );
}