import 'package:flutter/material.dart';
import 'station.dart';
import '../services/pathfinding_engine.dart';

Color lineColor(String line) {
  if (line == 'Red') return const Color(0xFFE53935);
  if (line == 'Blue') return const Color(0xFF1E88E5);
  return const Color(0xFF43A047);
}

class RouteOption {
  final List<Station> stations;
  final RoutePreference pref;
  final String title;

  RouteOption({required this.stations, required this.pref, required this.title});

  int get stops => stations.isEmpty ? 0 : stations.length - 1;
  int get transfers {
    int t = 0;
    for (int i = 0; i < stations.length - 1; i++) {
      if (stations[i].line != stations[i+1].line) t++;
    }
    return t;
  }
}
