class Station {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String line;
  final int orderIndex;

  Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.line,
    required this.orderIndex,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'],
      name: json['name'],
      lat: json['lat'].toDouble(),
      lng: json['lng'].toDouble(),
      line: json['line'],
      orderIndex: json['orderIndex'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lat': lat,
      'lng': lng,
      'line': line,
      'orderIndex': orderIndex,
    };
  }
}
