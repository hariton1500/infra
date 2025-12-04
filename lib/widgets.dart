import 'package:flutter/material.dart';

Widget ponBoxWidget(Map<String, dynamic> box, double zoom) {
  final int ports = (box['ports'] ?? 0) as int;
  final int used = (box['used_ports'] ?? 0) as int;
  final int id = (box['id'] ?? 0) as int;
  final double usage = ports > 0 ? (used / ports).clamp(0.0, 1.0) : 0.0;

  Color usageColor;
  if (usage >= 0.85) {
    usageColor = Colors.redAccent;
  } else if (usage >= 0.6) {
    usageColor = Colors.orange;
  } else {
    usageColor = Colors.green;
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      final double w = constraints.maxWidth;
      final double h = constraints.maxHeight;

      final double gap = (w * 0.06).clamp(2.0, 8.0);
      // Dynamic font sizing based on text length to avoid overflow when ports > 9
      final String capacityText = '$used/$ports'; // no spaces to save width
      final int capacityLen = capacityText.length;
      double fontMain = (w * 0.2).clamp(8.0, 18.0);
      // Heuristic: shrink font as the text grows
      final double suggested = (w * 0.75) / (capacityLen + 2);
      fontMain = suggested.clamp(8.0, fontMain);
      final double fontSub = (w * 0.14).clamp(6.0, 14.0);
      final double barHeight = (h * 0.12).clamp(4.0, 8.0);

      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: usageColor.withValues(alpha: 0.5), width: 2),
        ),
        padding: EdgeInsets.symmetric(horizontal: (w * 0.04).clamp(2.0, 6.0), vertical: (h * 0.08).clamp(2.0, 8.0)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (w * 0.72).clamp(20.0, double.infinity)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capacityText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontMain,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: usage,
                          minHeight: barHeight,
                          backgroundColor: Colors.black12,
                          valueColor: AlwaysStoppedAnimation<Color>(usageColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '# $id',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fontSub, color: Colors.black54, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget pillarWidget(double zoom) {
  return Container(
    //color: Colors.green,
    decoration: BoxDecoration(
      color: Colors.green,
      border: Border.all(
        color: Colors.black
      )
    ),
  );
}

Widget linkText(String text) {
  return Text('[ $text ]', style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Colors.blue),);
}