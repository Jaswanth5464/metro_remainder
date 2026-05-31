import 'dart:collection';
import 'package:collection/collection.dart';
import '../models/station.dart';

enum RoutePreference {
  fastest,
  fewestTransfers,
}

class _DijkstraNode {
  final String id;
  final double cost;
  final List<String> path;

  _DijkstraNode(this.id, this.cost, this.path);
}

class PathfindingEngine {
  // Graph mapping Station ID -> List of Connected Station IDs
  final Map<String, List<String>> _graph = {};
  final List<Station> _allStations;

  PathfindingEngine(this._allStations) {
    _buildGraph();
  }

  void _buildGraph() {
    // 1. Group stations by line
    final Map<String, List<Station>> lines = {};
    for (var s in _allStations) {
      lines.putIfAbsent(s.line, () => []).add(s);
    }

    // 2. Connect stations sequentially within the same line
    for (var line in lines.values) {
      line.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (int i = 0; i < line.length; i++) {
        _graph.putIfAbsent(line[i].id, () => []);
        
        if (i > 0) {
          _graph[line[i].id]!.add(line[i - 1].id);
        }
        if (i < line.length - 1) {
          _graph[line[i].id]!.add(line[i + 1].id);
        }
      }
    }

    // 3. Define the physical interchange nodes (Transfers) in Hyderabad
    // Ameerpet (Red <-> Blue)
    _addBiDirectionalConnection("S11", "S11_B"); 
    // MGBS (Red <-> Green)
    _addBiDirectionalConnection("S20", "S20_G"); 
    // Parade Ground (Blue <-> Green)
    _addBiDirectionalConnection("S36", "S50");
  }

  void _addBiDirectionalConnection(String id1, String id2) {
    _graph.putIfAbsent(id1, () => []).add(id2);
    _graph.putIfAbsent(id2, () => []).add(id1);
  }

  // Uses Dijkstra to find shortest path based on preference
  List<Station> getShortestPath(String startId, String targetId, {RoutePreference pref = RoutePreference.fastest}) {
    final pq = PriorityQueue<_DijkstraNode>((a, b) => a.cost.compareTo(b.cost));
    final Map<String, double> minCosts = {};
    
    pq.add(_DijkstraNode(startId, 0.0, [startId]));
    minCosts[startId] = 0.0;

    while (pq.isNotEmpty) {
      final current = pq.removeFirst();

      if (current.id == targetId) {
        return current.path.map((id) => _allStations.firstWhere((s) => s.id == id)).toList();
      }

      if (current.cost > (minCosts[current.id] ?? double.infinity)) {
        continue;
      }

      for (String neighborId in _graph[current.id] ?? []) {
        double edgeCost = 1.0;
        
        Station currentStation = _allStations.firstWhere((s) => s.id == current.id);
        Station neighborStation = _allStations.firstWhere((s) => s.id == neighborId);
        
        if (currentStation.line != neighborStation.line) {
          if (pref == RoutePreference.fewestTransfers) {
            edgeCost = 50.0; // Heavy penalty for transferring
          } else {
            edgeCost = 1.2; // Slight penalty for transferring
          }
        }
        
        double newCost = current.cost + edgeCost;
        if (newCost < (minCosts[neighborId] ?? double.infinity)) {
          minCosts[neighborId] = newCost;
          final newPath = List<String>.from(current.path)..add(neighborId);
          pq.add(_DijkstraNode(neighborId, newCost, newPath));
        }
      }
    }

    return []; // No path found
  }
}
