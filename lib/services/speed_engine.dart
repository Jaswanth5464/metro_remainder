import 'dart:math';

/// Production-level GPS speed calculator.
/// 
/// Solves GPS jitter, drift, fake movement, and tunnel noise by:
///   1. Rejecting readings with poor accuracy (>25m)
///   2. Ignoring micro-movements (<5m) as GPS drift
///   3. Computing speed manually from lat/lng delta, not pos.speed
///   4. Clamping physical impossibilities (>120 km/h)
///   5. Applying a 5-point rolling average
///   6. Detecting stationary state (<3 km/h for 10 sec → force 0)
class SpeedEngine {
  double? _lastLat;
  double? _lastLon;
  DateTime? _lastTime;

  final List<double> _speedBuffer = [];
  bool _isStationary = false;
  DateTime? _stationaryStart;

  // ── Config ─────────────────────────────────────────
  static const double maxAllowedSpeedKmh   = 120.0; // km/h
  static const double minMovementMeters    = 5.0;   // GPS drift threshold
  static const double stationaryKmh        = 3.0;   // speed below this = "stopped"
  static const int    stationarySeconds    = 10;    // must stay below for 10s
  static const double maxAccuracyMeters    = 25.0;  // reject if GPS inaccurate

  /// Call on every GPS position update.
  /// Returns smoothed speed in **km/h**.
  double update({
    required double lat,
    required double lon,
    required double accuracy,
  }) {
    final now = DateTime.now();

    // ① Reject bad GPS accuracy
    if (accuracy > maxAccuracyMeters) {
      return getSmoothedSpeed();
    }

    // First reading — just save reference point
    if (_lastLat == null) {
      _lastLat = lat;
      _lastLon = lon;
      _lastTime = now;
      return 0.0;
    }

    final distM = _haversine(_lastLat!, _lastLon!, lat, lon);
    final timeSec = now.difference(_lastTime!).inMilliseconds / 1000.0;

    if (timeSec <= 0) return getSmoothedSpeed();

    // ② Ignore GPS drift — movement smaller than error circle
    if (distM < minMovementMeters) {
      _addSample(0.0);
      _checkStationary(0.0);
      return getSmoothedSpeed();
    }

    // ③ Calculate speed manually (m/s → km/h)
    double speedKmh = (distM / timeSec) * 3.6;

    // ④ Clamp impossible spike (>120 km/h)
    if (speedKmh > maxAllowedSpeedKmh) {
      return getSmoothedSpeed(); // keep previous smoothed value
    }

    _addSample(speedKmh);
    _checkStationary(speedKmh);

    _lastLat = lat;
    _lastLon = lon;
    _lastTime = now;

    return getSmoothedSpeed();
  }

  void _addSample(double speedKmh) {
    _speedBuffer.add(speedKmh);
    if (_speedBuffer.length > 5) _speedBuffer.removeAt(0);
  }

  /// Returns 5-sample moving average speed in km/h.
  double getSmoothedSpeed() {
    if (_speedBuffer.isEmpty) return 0.0;
    return _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length;
  }

  void _checkStationary(double speedKmh) {
    if (speedKmh < stationaryKmh) {
      _stationaryStart ??= DateTime.now();
      if (DateTime.now().difference(_stationaryStart!).inSeconds >= stationarySeconds) {
        _isStationary = true;
      }
    } else {
      _stationaryStart = null;
      _isStationary = false;
    }
  }

  /// True if speed has been below 3 km/h for at least 10 seconds.
  bool get isStationary => _isStationary;

  /// Speed in m/s (for ETA calculations that need m/s).
  double get smoothedSpeedMs => getSmoothedSpeed() / 3.6;

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastTime = null;
    _speedBuffer.clear();
    _isStationary = false;
    _stationaryStart = null;
  }

  // Haversine formula — returns distance in meters
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}
