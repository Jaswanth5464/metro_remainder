import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/station.dart';
import '../models/journey.dart';
import '../data/database_helper.dart';
import '../services/alarm_service.dart';
import '../services/speed_engine.dart';
import '../models/route_option.dart';
import 'home_screen.dart' show HomeScreen;

class LiveJourneyScreen extends StatefulWidget {
  final Station destination;
  final RouteOption route;

  const LiveJourneyScreen({
    super.key,
    required this.destination,
    required this.route,
  });

  @override
  State<LiveJourneyScreen> createState() => _LiveJourneyScreenState();
}

class _LiveJourneyScreenState extends State<LiveJourneyScreen> with TickerProviderStateMixin {
  // ── Data ──────────────────────────────────────
  List<Station> _waypoints = [];
  int _wpIdx = 0; // Represents the index in _waypoints array
  int _fullRouteIndex = 0; // Represents the exact index in widget.route.stations
  
  List<Polyline> _baseLines = [];
  List<Polyline> _routeLines = [];

  // ── Live location ──────────────────────────────
  ValueNotifier<LatLng?> _myPos = ValueNotifier(null);
  StreamSubscription<Position>? _locSub;
  ValueNotifier<double> _distToNextKm = ValueNotifier(0);
  ValueNotifier<int> _etaSec = ValueNotifier(0);
  ValueNotifier<String> _status = ValueNotifier('Waiting for GPS');
  ValueNotifier<double> _speedKmh = ValueNotifier(0);
  DateTime? _lastGpsTime;


  // Active Alarm State
  int _activeAlarmStage = 0;
  String _alarmStationName = "";
  bool _alarmIsTransfer = false;
  String? _alarmNextLine;
  String? _alarmNextStation;

  // ── Map ────────────────────────────────────────
  final MapController _mapCtl = MapController();
  // ── Animations ─────────────────────────────────
  late AnimationController _pulseCtl;
  late Animation<double> _pulse;
  late AnimationController _dotCtl;
  late Animation<double> _dot;

  @override
  void initState() {
    super.initState();
    _pulseCtl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _pulse = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));
    _dotCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _dot = Tween(begin: 0.4, end: 1.0).animate(_dotCtl);

    _setupMapData();
    _startJourney();
    _listenToService();
    _startGPS();
  }

  @override
  void dispose() {
    _pulseCtl.dispose();
    _dotCtl.dispose();
    _myPos.dispose();
    _distToNextKm.dispose();
    _etaSec.dispose();
    _status.dispose();
    _speedKmh.dispose();
    _locSub?.cancel();
    super.dispose();
  }

  void _setupMapData() {
    // 1. Convert Route Option into map elements
    final path = widget.route.stations;
    
    // Route polylines
    List<Polyline> rlines = [];
    for (int i = 0; i < path.length - 1; i++) {
      rlines.add(Polyline(
        points: [LatLng(path[i].lat, path[i].lng), LatLng(path[i + 1].lat, path[i + 1].lng)],
        color: lineColor(path[i].line),
        strokeWidth: 6,
      ));
    }
    
    // Waypoints
    List<Station> wps = [];
    for (int i = 0; i < path.length - 1; i++) {
      if (path[i].line != path[i + 1].line) wps.add(path[i]);
    }
    if (path.isNotEmpty) wps.add(path.last);

    setState(() {
      _routeLines = rlines;
      _waypoints = wps;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (path.isNotEmpty) {
        _mapCtl.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(path.map((s) => LatLng(s.lat, s.lng)).toList()),
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 360),
        ));
      }
    });
  }

  // ── GPS ─────────────────────────────────────────
  Future<void> _startGPS() async {
    // GPS only works reliably on Android/iOS. On desktop, geolocator
    // sends events on a non-platform thread which causes crashes.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, 
        distanceFilter: 0,
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position pos) {
    // Math logic to snap coordinate to the current route segment
    LatLng rawPos = LatLng(pos.latitude, pos.longitude);
    LatLng snappedPos = _snapToRoute(rawPos, _fullRouteIndex);

    _myPos.value = snappedPos;
    _lastGpsTime = DateTime.now();
  }

  LatLng _snapToRoute(LatLng rawPos, int rIdx) {
    final route = widget.route.stations;
    if (rIdx >= route.length - 1) return rawPos;
    
    Station A = route[rIdx];
    Station B = route[rIdx + 1];

    double px = rawPos.longitude;
    double py = rawPos.latitude;
    double ax = A.lng;
    double ay = A.lat;
    double bx = B.lng;
    double by = B.lat;

    double dx = bx - ax;
    double dy = by - ay;
    
    if (dx == 0 && dy == 0) return LatLng(ay, ax);
    
    double t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    t = math.max(0, math.min(1, t)); // clamp
    
    return LatLng(ay + t * dy, ax + t * dx);
  }

  void _listenToService() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterBackgroundService().on('update').listen((e) {
      if (e == null || !mounted) return;
      double speed = ((e['speedKmh'] ?? 0) as num).toDouble();
      double dist = ((e['distance'] ?? 0) as num).toDouble();
      String mode = e['mode'] as String? ?? 'CRUISING';
      int routeIndex = e['routeIndex'] as int? ?? 0;
      
      _status.value = mode;
      _distToNextKm.value = dist / 1000.0;
      _etaSec.value = speed > 0 ? (dist / (speed * 1000 / 3600)).round() : 0;
      _speedKmh.value = speed;
      
      // Calculate active waypoint index based on constrained route progression
      int targetWpIdx = 0;
      for (int i = 0; i < _waypoints.length; i++) {
        int wpRouteIdx = widget.route.stations.indexWhere((s) => s.id == _waypoints[i].id);
        if (routeIndex >= wpRouteIdx && i < _waypoints.length - 1) {
           targetWpIdx = i + 1; // Passed it, look at next
        } else if (routeIndex < wpRouteIdx) { // Haven't reached
           targetWpIdx = i;
           break;
        } else { // Reached final definition
           targetWpIdx = i;
        }
      }

      setState(() {
         _fullRouteIndex = routeIndex;
         _wpIdx = targetWpIdx; // Safe sync UI rendering index
      });
    });
    FlutterBackgroundService().on('alarm_stage_triggered').listen((e) {
      if (e == null || !mounted) return;
      
      int stage = e['stage'] as int? ?? 1;
      String stationName = e['station'] as String? ?? 'Destination';
      bool isTransfer = e['isTransfer'] as bool? ?? false;
      
      setState(() {
        _activeAlarmStage = stage;
        _alarmStationName = stationName;
        _alarmIsTransfer = isTransfer;
      });
    });
    FlutterBackgroundService().on('journey_stopped').listen((e) {
      _stopJourney(reason: e?['reason'] ?? 'Journey complete.');
    });
  }

  // ── Journey lifecycle ─────────────────────────────
  Future<void> _startJourney() async {
    final startId = widget.route.stations.first.id;
    await DatabaseHelper.instance.createJourney(Journey(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startStationId: startId,
      destinationStationId: widget.destination.id,
      startTime: DateTime.now().toIso8601String(),
      active: 1,
    ));
    if (Platform.isAndroid || Platform.isIOS) {
      final svc = FlutterBackgroundService();
      
      if (Platform.isAndroid) {
        final flnPlugin = FlutterLocalNotificationsPlugin();
        await flnPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }

      if (!await svc.isRunning()) await svc.startService();
      else svc.invoke('setAsForeground');
    }
  }

  void _stopJourney({String reason = 'Journey cancelled.'}) {
    AlarmService().stopAlarm();
    if (Platform.isAndroid || Platform.isIOS) FlutterBackgroundService().invoke('stopService');
    DatabaseHelper.instance.stopActiveJourney();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason), backgroundColor: const Color(0xFF34C759), behavior: SnackBarBehavior.floating),
      );
      // Navigate back to Home
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (c) => HomeScreen()),
        (r) => false
      );
    }
  }

  // ── UI helpers ─────────────────────────────────────
  int get _stopsToNext {
    if (widget.route.stations.isEmpty || _wpIdx >= _waypoints.length) return 0;
    final nextWp = _waypoints[_wpIdx];
    int idx = widget.route.stations.indexWhere((s) => s.id == nextWp.id);
    return idx >= 0 ? idx : 0;
  }

  String get _etaString {
    if (_etaSec.value <= 0) return '--';
    if (_etaSec.value < 60) return '< 1 min';
    final m = _etaSec.value ~/ 60;
    final s = _etaSec.value % 60;
    return '$m min ${s.toString().padLeft(2, '0')} sec';
  }

  // ═══════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldEnd = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('End journey?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text(
              'Your journey is still active. Tap "I Got Down" to end it, or stay on this screen.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay', style: TextStyle(color: Colors.blueAccent)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () { Navigator.pop(context, true); },
                child: const Text('End Journey', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (shouldEnd == true && context.mounted) {
          _stopJourney(reason: 'Journey ended by user.');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
        // ── MAP (Fallback enabled) ────────────────
        Stack(
          children: [
            // Fallback Offline Map
            Image.asset(
              'assets/metro_map.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_,__,___) => const SizedBox(), // Hide if missing
            ),
            
            // Interactive Map
            FlutterMap(
              mapController: _mapCtl,
              options: const MapOptions(initialCenter: LatLng(17.4357, 78.4447), initialZoom: 12.5),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.metro_wake',
                  // Map will naturally fail to load tiles if offline, revealing fallback
                ),
                PolylineLayer(polylines: _routeLines),
                MarkerLayer(markers: [
                  // Station dots
                  ...widget.route.stations.map((s) => Marker(
                    point: LatLng(s.lat, s.lng),
                    width: 64, height: 28,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: lineColor(s.line),
                        border: Border.all(color: Colors.white, width: 1.2),
                      )),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                    ]),
                  )),
                ]),
                // My live location dot (Separate Builder Layer)
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _myPos,
                  builder: (context, pos, child) {
                    if (pos == null) return const SizedBox();
                    return MarkerLayer(markers: [
                      Marker(
                        point: pos,
                        width: 40, height: 40,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => Stack(alignment: Alignment.center, children: [
                            Container(
                              width: 40 * _pulse.value,
                              height: 40 * _pulse.value,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent.withOpacity(0.25 * (1.5 - _pulse.value))),
                            ),
                            Container(width: 14, height: 14, decoration: BoxDecoration(
                              shape: BoxShape.circle, color: Colors.white,
                              border: Border.all(color: Colors.blueAccent, width: 3),
                              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 8)],
                            )),
                          ]),
                        ),
                      )
                    ]);
                  }
                ),
              ],
            ),
          ],
        ),

        // ── TOP BAR ──────────────────────────────────
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            _pill(Icons.directions_subway_rounded, 'Live Journey', Colors.white12, Colors.white),
            const Spacer(),
            ValueListenableBuilder<String>(
              valueListenable: _status,
              builder: (context, statusStr, child) {
                return IconButton(
                  icon: const Icon(Icons.share_rounded, color: Colors.greenAccent, size: 26),
                  tooltip: 'Share Live Journey',
                  onPressed: () => _shareJourneyWhatsApp(statusStr),
                );
              }
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<LatLng?>(
              valueListenable: _myPos,
              builder: (context, pos, child) {
                if (pos != null) {
                  return _pill(Icons.my_location, 'Live GPS', Colors.blueAccent.withOpacity(0.2), Colors.blueAccent);
                }
                return const SizedBox();
              }
            ),
          ]),
        )),

        // ── BOTTOM PANEL ─────────────────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14).withOpacity(0.94),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: const Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                   _trackingPanel(),
                ]),
              ),
            ),
          ),
        ),
        
        // Alarm Takeover Layer
        if (_activeAlarmStage > 0)
          Positioned.fill(
             child: _AlarmTakeover(
               stage: _activeAlarmStage,
               stationName: _alarmStationName,
               isTransfer: _alarmIsTransfer,
               nextLine: _alarmNextLine,
               nextStation: _alarmNextStation,
               destinationStation: widget.destination,
               accentColor: _alarmIsTransfer ? Colors.orange.shade900 : lineColor(widget.destination.line),
               onDismiss: () {
                 FlutterBackgroundService().invoke('dismiss_alarm', {'stage': _activeAlarmStage});
                 setState(() => _activeAlarmStage = 0);
               },
               onStopJourney: () {
                 FlutterBackgroundService().invoke('dismiss_alarm', {'stage': _activeAlarmStage});
                 setState(() => _activeAlarmStage = 0);
                 _stopJourney(reason: 'Arrived at $_alarmStationName!');
               },
             ),
          ),
      ]),
      ),  // end Scaffold
    );  // end PopScope
  }

  // ── TRACKING PANEL ────────────────────────────────
  Widget _trackingPanel() {
    final nextWp = _wpIdx < _waypoints.length ? _waypoints[_wpIdx] : widget.destination;
    final lineC = lineColor(nextWp.line);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Status badge
      Row(children: [
        AnimatedBuilder(animation: _dot, builder: (_, __) => Container(
          width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: lineC.withOpacity(_dot.value)),
        )),
        const SizedBox(width: 8),
        ValueListenableBuilder<String>(
          valueListenable: _status,
          builder: (context, statusStr, child) {
            Color statusColor = statusStr == 'Stopped' ? Colors.orange : statusStr == 'Approaching station' ? Colors.yellow : lineC;
            return Text(statusStr.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2));
          }
        ),
      ]),
      const SizedBox(height: 10),

      // NEXT station
      const Text('NEXT STOP', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
      const SizedBox(height: 4),
      Text(nextWp.name, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1)), // Massive Font

      // Arrival ETA
      ValueListenableBuilder<int>(
        valueListenable: _etaSec,
        builder: (context, eta, child) {
          if (eta <= 0) return const SizedBox();
          String etaStr = (eta >= 60) ? '${eta ~/ 60}m ${eta % 60}s' : '${eta}s';
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Arriving in $etaStr', style: TextStyle(color: lineC, fontSize: 18, fontWeight: FontWeight.w600)),
          );
        }
      ),
      const SizedBox(height: 24),

      // Journey progress (waypoint circles)
      _journeyProgress(lineC),
      const SizedBox(height: 20),

      // Speed & distance row
      ValueListenableBuilder<double>(
        valueListenable: _distToNextKm,
        builder: (context, distKm, child) {
          return ValueListenableBuilder<double>(
            valueListenable: _speedKmh,
            builder: (context, speed, child) {
              final String speedLabel = '${speed.toStringAsFixed(0)} km/h';
              return Row(children: [
                Expanded(child: _infoTile(
                  Icons.speed_rounded,
                  speedLabel,
                  'Speed',
                  lineC,
                )),
                const SizedBox(width: 10),
                Expanded(child: _infoTile(
                  Icons.near_me_rounded,
                  '${distKm.toStringAsFixed(2)} km',
                  'To destination',
                  lineC,
                )),
              ]);
            }
          );
        }
      ),
      const SizedBox(height: 16),

      // I GOT DOWN button
      SizedBox(
        width: double.infinity, height: 58,
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            _stopJourney();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF3B30),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('I GOT DOWN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      ),
    ]);
  }

  Widget _journeyProgress(Color lineC) {
    if (_waypoints.isEmpty) return const SizedBox();
    List<Station> nodes = [widget.route.stations.first, ..._waypoints];
    if (nodes.length > 1 && nodes.first.id == nodes[1].id) nodes.removeAt(0);

    return Row(children: [
      for (int i = 0; i < nodes.length; i++) ...[
        _progressDot(nodes[i], i, lineC),
        if (i < nodes.length - 1)
          Expanded(child: Container(
            height: 2,
            color: i < _wpIdx ? lineC : Colors.white12,
          )),
      ],
    ]);
  }

  Widget _progressDot(Station s, int nodeIdx, Color lineC) {
    bool isPast = nodeIdx < _wpIdx;
    bool isCurrent = nodeIdx == _wpIdx;
    Color c = lineColor(s.line);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: isCurrent ? 16 : 10,
        height: isCurrent ? 16 : 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPast || isCurrent ? c : Colors.transparent,
          border: Border.all(color: isCurrent ? Colors.white : c, width: isCurrent ? 3 : 1.5),
          boxShadow: isCurrent ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 8)] : [],
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(width: 60, child: Text(
        s.name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? Colors.white : isPast ? c.withOpacity(0.6) : Colors.white30,
          fontSize: 9,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      )),
    ]);
  }

  Widget _infoTile(IconData icon, String value, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _pill(IconData icon, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  void _shareJourneyWhatsApp(String currentStatus) async {
    final startStName = widget.route.stations.first.name;
    final destStName = widget.destination.name;
    final nextWpName = _wpIdx < _waypoints.length ? _waypoints[_wpIdx].name : widget.destination.name;
    final etaStr = _etaString;
    
    final message = "🚇 *Metro Journey*\nFrom: $startStName\nTo: $destStName\n\n📍 *Current Status*: $currentStatus\n➡️ *Next Station*: $nextWpName\n⏱️ *ETA*: $etaStr\n\n_Sent from Metro Reminder App_";
    
    final uri = Uri.parse("whatsapp://send?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp is not installed.')));
      }
    }
  }
}

// ═══════════════════════════════════════════════════════
// FULL-SCREEN ALARM TAKEOVER (Multi-Stage)
// ═══════════════════════════════════════════════════════
class _AlarmTakeover extends StatefulWidget {
  final int stage;
  final String stationName;
  final bool isTransfer;
  final String? nextLine;
  final String? nextStation;
  final Station? destinationStation; // Needed for ride booking loc
  final Color accentColor;
  final VoidCallback onDismiss;
  final VoidCallback onStopJourney;

  const _AlarmTakeover({
    required this.stage,
    required this.stationName,
    required this.isTransfer,
    this.nextLine,
    this.nextStation,
    this.destinationStation,
    required this.accentColor,
    required this.onDismiss,
    required this.onStopJourney,
  });

  @override
  State<_AlarmTakeover> createState() => _AlarmTakeoverState();
}

class _AlarmTakeoverState extends State<_AlarmTakeover> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _pulse = Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String stageText = widget.stage == 1 ? "3 MIN WARNING" : widget.stage == 2 ? "90 SEC WARNING" : "ARRIVING NOW";
    Color pulseColor = widget.stage == 1 ? Colors.blue.shade900 : widget.stage == 2 ? Colors.orange.shade900 : widget.accentColor;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        decoration: BoxDecoration(gradient: RadialGradient(
          center: Alignment.center, radius: 1.2,
          colors: [pulseColor.withOpacity(_pulse.value), Colors.black],
        )),
        child: SafeArea(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          // Icon
          Center(child: Container(
            width: 90, height: 90,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.15), border: Border.all(color: Colors.white30, width: 2)),
            child: Icon(widget.isTransfer ? Icons.swap_horiz : Icons.notifications_active_rounded, color: Colors.white, size: 44),
          )),
          const SizedBox(height: 32),
          // Main label
          Center(child: Text(stageText, style: const TextStyle(color: Colors.white70, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          Center(child: Text(widget.stationName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1))),
          if (widget.isTransfer && widget.nextStation != null) ...[
            const SizedBox(height: 12),
            Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
              child: Text('Board ${widget.nextLine} Line → ${widget.nextStation}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            )),
          ] else ...[
            const SizedBox(height: 12),
            Center(child: Text(widget.isTransfer ? 'Get ready to transfer' : 'Get ready to disembark', style: const TextStyle(color: Colors.white54, fontSize: 18))),
          ],
          const Spacer(),
          
          if (widget.stage < 3)
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 40),
               child: ElevatedButton(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.white24,
                   padding: const EdgeInsets.symmetric(vertical: 18),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                 ),
                 onPressed: widget.onDismiss,
                 child: const Text('ACKNOWLEDGE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
               ),
             ),
             
          const SizedBox(height: 20),
          
          if (!widget.isTransfer && widget.stage == 3 && widget.destinationStation != null) ...[
            // Last-Mile Ride Booking Buttons (Only show at final destination stage 3)
            const Center(child: Text("Book a ride from the station", style: TextStyle(color: Colors.white70, fontSize: 14))),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _rideButton('Uber', Icons.local_taxi, Colors.black, Colors.white, () => _launchRideApp('uber')),
                const SizedBox(width: 12),
                _rideButton('Rapido', Icons.two_wheeler_rounded, const Color(0xFFF9C61A), Colors.black, () => _launchRideApp('rapido')),
                const SizedBox(width: 12),
                _rideButton('Ola', Icons.local_taxi_rounded, const Color(0xFFC0E218), Colors.black, () => _launchRideApp('ola')),
              ],
            ),
            const SizedBox(height: 24),
          ],
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: pulseColor,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: widget.onStopJourney,
              child: Text(widget.isTransfer && widget.stage < 3 ? 'SKIP THIS TRANSFER' : "I GOT DOWN", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(height: 40),
        ])),
      ),
    );
  }

  Widget _rideButton(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) {
     return InkWell(
       onTap: onTap,
       borderRadius: BorderRadius.circular(12),
       child: Container(
         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
         decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
         child: Row(children: [
           Icon(icon, color: fg, size: 20),
           const SizedBox(width: 6),
           Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
         ]),
       ),
     );
  }

  void _launchRideApp(String app) async {
    final lat = widget.destinationStation!.lat;
    final lng = widget.destinationStation!.lng;
    
    // Universal fallback URL is google maps directed
    String url = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    
    if (app == 'uber') {
      // Intent URL scheme for Uber
      url = "uber://?action=setPickup&pickup=my_location&dropoff[latitude]=$lat&dropoff[longitude]=$lng&dropoff[nickname]=${Uri.encodeComponent(widget.destinationStation!.name)}";
    } else if (app == 'rapido') {
      // Rapido universal link or intent (rapido doesn't have public dropoff params easily available without api, just launching app)
      url = "rapido://"; 
    } else if (app == 'ola') {
       // Ola intent
       url = "olacabs://app/launch?lat=$lat&lat=$lng";
    }

    Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback
      uri = Uri.parse("https://play.google.com/store/apps/details?id=" + 
        (app == 'uber' ? 'com.ubercab' : app == 'rapido' ? 'com.rapido.passenger' : 'com.olacabs.customer'));
      await launchUrl(uri);
    }
  }
}
