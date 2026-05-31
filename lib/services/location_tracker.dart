import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../data/database_helper.dart';
import '../models/station.dart';
import '../models/journey.dart';
import '../services/pathfinding_engine.dart';
import '../services/speed_engine.dart';
import '../services/alarm_service.dart';

enum JourneyState { idle, moving, approaching, atStation, transition, tunnel }

class LocationTracker {
  final ServiceInstance service;

  StreamSubscription<Position>? _positionStreamSubscription;
  Journey? _activeJourney;
  Station? _destinationStation;
  
  List<Station> _allStations = [];
  List<Station> _fullRoute = [];
  int _routeIndex = 0;
  
  Station? _targetWaypoint;
  int _targetWaypointIndex = -1;
  bool _isTransferWaypoint = false;
  
  JourneyState _state = JourneyState.idle;

  // Speed Engine (production-grade noise filtering)
  final SpeedEngine _speedEngine = SpeedEngine();
  
  // State
  DateTime? _lastValidGpsTime;
  double _lastDistanceMeters = 0.0;
  int _movingAwayCounter = 0;
  int _stationaryCounter = 0;
  Timer? _tunnelDeadReckoningTimer;
  bool _isStationary = false;

  int _maxDismissedStage = 0;
  int _currentAlarmStage = 0;

  LocationTracker(this.service);

  Future<void> startTracking() async {
    _activeJourney = await DatabaseHelper.instance.getActiveJourney();
    if (_activeJourney == null) {
      service.stopSelf();
      return;
    }

    _destinationStation = await DatabaseHelper.instance
        .getStationById(_activeJourney!.destinationStationId);

    _allStations = await DatabaseHelper.instance.getAllStations();

    if (_destinationStation == null || _allStations.isEmpty) {
      service.stopSelf();
      return;
    }

    // Initialize Constrained Route
    final engine = PathfindingEngine(_allStations);
    _fullRoute = engine.getShortestPath(_activeJourney!.startStationId, _destinationStation!.id);
    if (_fullRoute.isEmpty) {
      service.stopSelf();
      return;
    }
    
    _routeIndex = 0;
    _updateTargetWaypoint();
    _state = JourneyState.moving;

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Tracking active journey...",
        notificationTitle: "Metro Wake-Up",
        enableWakeLock: true,
      ),
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings)
        .listen((Position position) {
      _processLocation(position);
    });

    service.on('dismiss_alarm').listen((event) {
      int stage = event?['stage'] ?? 1;
      _maxDismissedStage = stage;
      AlarmService().stopAlarm();
      _currentAlarmStage = 0;
      
      // If we are at/near transfer, forcefully transition to next leg
      if (_isTransferWaypoint && _lastDistanceMeters < 500) {
        if (_routeIndex < _targetWaypointIndex) {
          _routeIndex = _targetWaypointIndex;
        }
        _routeIndex++; // Advance to next line's first segment
        if (_routeIndex >= _fullRoute.length) _routeIndex = _fullRoute.length - 1;
        _updateTargetWaypoint();
        _maxDismissedStage = 0;
        _state = JourneyState.transition;
      }
    });

    _tunnelDeadReckoningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tunnelTick();
    });
  }

  void _updateTargetWaypoint() {
    for (int i = _routeIndex + 1; i < _fullRoute.length; i++) {
        if (i == _fullRoute.length - 1 || _fullRoute[i].line != _fullRoute[i+1].line) {
            _targetWaypoint = _fullRoute[i];
            _targetWaypointIndex = i;
            _isTransferWaypoint = i != _fullRoute.length - 1;
            break;
        }
    }
  }

  void _tunnelTick() {
    if (_targetWaypoint == null || _lastValidGpsTime == null) return;
    
    final secondsSinceLastGps = DateTime.now().difference(_lastValidGpsTime!).inSeconds;
    
    if (secondsSinceLastGps > 15 && !_isStationary) {
      _state = JourneyState.tunnel;
      double speedMs = _speedEngine.smoothedSpeedMs;
      if (speedMs > 0) {
        _lastDistanceMeters -= speedMs;
        if (_lastDistanceMeters < 0) _lastDistanceMeters = 0;

        _triggerUpdates();

        if (_lastDistanceMeters <= 500 && _maxDismissedStage < 3) {
          _triggerAlarmStage(3);
        }
      }
    }
  }

  void _processLocation(Position position) async {
    if (_targetWaypoint == null) return;
    if (position.accuracy > 100) return;
    
    _lastValidGpsTime = DateTime.now();

    // 1. Constrained Station Tracking
    int bestIdx = _routeIndex;
    double minD = double.infinity;
    for (int i = _routeIndex; i <= math.min(_routeIndex + 2, _fullRoute.length - 1); i++) {
      double d = _calculateDistance(position.latitude, position.longitude, _fullRoute[i].lat, _fullRoute[i].lng);
      if (d < minD) { minD = d; bestIdx = i; }
    }
    
    if (bestIdx > _routeIndex && minD < 400) { 
      // We advanced a station
      _routeIndex = bestIdx;
      _updateTargetWaypoint();
    }

    final double currentSpeedKmh = _speedEngine.update(
      lat: position.latitude,
      lon: position.longitude,
      accuracy: position.accuracy,
    );
    final bool stationary = _speedEngine.isStationary;

    if (stationary) {
      _stationaryCounter++;
      if (_stationaryCounter > 120 && _stationaryCounter % 10 != 0) return;
    } else {
      _stationaryCounter = 0;
    }

    double distanceMeters = _calculateDistance(
        position.latitude, position.longitude,
        _targetWaypoint!.lat, _targetWaypoint!.lng);

    if (_lastDistanceMeters > 0 && distanceMeters > _lastDistanceMeters + 10) {
      _movingAwayCounter++;
      if (_movingAwayCounter >= 25 && _lastDistanceMeters > 500) { // Don't false-trigger stop at station
        _stopJourneyWithMessage("You are moving away from the destination.");
        return;
      }
    } else {
      _movingAwayCounter = 0;
    }

    _isStationary = stationary;
    _lastDistanceMeters = distanceMeters;
    
    // Tiered Arrival Logic (Revised)
    if (_routeIndex >= _targetWaypointIndex) {
      _state = JourneyState.atStation;
      if (_maxDismissedStage < 4) { // 4 is hard stop
         _triggerAlarmStage(3);
      }
    } else {
      if (distanceMeters < 500) {
        _state = JourneyState.approaching;
        if (_maxDismissedStage < 3) _triggerAlarmStage(3);
      } else if (distanceMeters < 1000) {
        _state = JourneyState.approaching;
        if (_maxDismissedStage < 2) _triggerAlarmStage(2);
      } else if (_targetWaypointIndex - _routeIndex == 1 && minD < 300) {
        // Just reached the station preceding the target!
        _state = JourneyState.moving;
        if (_maxDismissedStage < 1) _triggerAlarmStage(1);
      } else {
        _state = JourneyState.moving;
      }
    }

    _triggerUpdates();
  }

  void _triggerUpdates() {
    String modeStr = _state.name.toUpperCase();
    
    if (service is AndroidServiceInstance) {
      final speedKmhLocal = _speedEngine.getSmoothedSpeed();
      final String timeEst = speedKmhLocal > 0
          ? ((_lastDistanceMeters / (1000.0 / 3600.0 * speedKmhLocal)) / 60).toStringAsFixed(1)
          : "--";
          
      String journeyTitle = _activeJourney != null && _destinationStation != null
          ? "${_allStations.firstWhere((s) => s.id == _activeJourney!.startStationId, orElse: () => _activeJourney!.startStationId as Station).name} to ${_destinationStation!.name}"
          : "Active Metro Journey";
          
      String subText = _isTransferWaypoint 
          ? "Next: Transfer at ${_targetWaypoint!.name} (${(_lastDistanceMeters/1000).toStringAsFixed(2)} km)"
          : "Next: ${_targetWaypoint!.name} (${(_lastDistanceMeters/1000).toStringAsFixed(2)} km)";
          
      (service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: journeyTitle,
        content: "$subText • ETA: $timeEst min • $modeStr",
      );
    }

    service.invoke(
      'update',
      {
        "distance": _lastDistanceMeters,
        "speedKmh": _speedEngine.getSmoothedSpeed(),
        "mode": modeStr,
        "isStationary": _isStationary,
        "routeIndex": _routeIndex,
        "targetIndex": _targetWaypointIndex,
      },
    );
  }

  void _stopJourneyWithMessage(String message) {
    service.invoke('journey_stopped', {"reason": message});
    stop();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    final double a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  void _triggerAlarmStage(int stage) {
    if (_currentAlarmStage == stage && stage != 3) return; 
    _currentAlarmStage = stage;
    
    AlarmStage aStage = AlarmStage.none;
    if (stage == 1) aStage = AlarmStage.stage1;
    if (stage == 2) aStage = AlarmStage.stage2;
    if (stage == 3) aStage = AlarmStage.stage3;
    
    AlarmService().triggerStage(aStage);
    
    String? nextLine;
    String? nextStationAfterTransfer;
    if (_isTransferWaypoint && _targetWaypointIndex + 1 < _fullRoute.length) {
       nextLine = _fullRoute[_targetWaypointIndex + 1].line;
       nextStationAfterTransfer = _fullRoute[_targetWaypointIndex + 1].name;
    }

    service.invoke('alarm_stage_triggered', {
       "stage": stage,
       "station": _targetWaypoint?.name ?? "Destination",
       "isTransfer": _isTransferWaypoint,
       "nextLine": nextLine,
       "nextStation": nextStationAfterTransfer,
    });
  }

  void stop() {
    _tunnelDeadReckoningTimer?.cancel();
    _positionStreamSubscription?.cancel();
    DatabaseHelper.instance.stopActiveJourney();
    service.stopSelf();
  }
}
