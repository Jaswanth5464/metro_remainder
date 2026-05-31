class Journey {
  final String id;
  final String startStationId;
  final String destinationStationId;
  final String startTime;
  final int active; // 1 = true, 0 = false for SQLite

  Journey({
    required this.id,
    required this.startStationId,
    required this.destinationStationId,
    required this.startTime,
    required this.active,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startStationId': startStationId,
      'destinationStationId': destinationStationId,
      'startTime': startTime,
      'active': active,
    };
  }

  factory Journey.fromMap(Map<String, dynamic> map) {
    return Journey(
      id: map['id'],
      startStationId: map['startStationId'] ?? '', // Default for old data
      destinationStationId: map['destinationStationId'],
      startTime: map['startTime'],
      active: map['active'],
    );
  }

  // Phase 1 Edge Cases & Pathfinding (Dijkstra's conceptualized for UI)
  static List<String> calculateTransferRoute(String startStationId, String endStationId, List<dynamic> allStations) {
    // In a real weighted graph we would use Dijkstra's Algorithm here. 
    // Since Hyderabad Metro is a simple 3-line intersecting cross:
    // Ameerpet (Red/Blue), MGBS (Red/Green), JBS Parade (Blue/Green)
    
    // For Phase 1, we will mock the return structure of the calculated path
    // e.g., ["Chikkadpally", "RTC Cross Roads", "Musheerabad", "Gandhi Hospital", "Secunderabad West", "JBS Parade Ground", "TRANSFER_BLUE", "Paradise", "Rasoolpura", "Prakash Nagar", "Begumpet", "Ameerpet", "Madhura Nagar", "Yusufguda", "Road No 5 Jubilee Hills", "Jubilee Hills Check Post", "Peddamma Temple", "Madhapur", "Durgam Cheruvu", "HITEC City", "Raidurg"]
    
    // Detailed routing graph implementation will be injected directly into the Map UI Polyline builder next.
    return [startStationId, "...", endStationId]; 
  }
}
