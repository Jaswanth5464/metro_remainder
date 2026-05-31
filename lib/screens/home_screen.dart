import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/station.dart';
import '../data/database_helper.dart';
import '../services/pathfinding_engine.dart';
import '../models/route_option.dart';
import 'route_selection_screen.dart';
import 'offline_map/offline_map_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Station> _stations = [];
  Station? _dest;
  Station? _nearStation;
  List<Map<String, dynamic>> _favorites = [];
  bool _isOutsideCoverage = false;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  // ── Data ─────────────────────────────────────────
  Future<void> _loadStations() async {
    final s = await DatabaseHelper.instance.getAllStations();
    final favs = await DatabaseHelper.instance.getFavorites();

    Station? nearest;
    bool outside = false;
    if (Platform.isAndroid || Platform.isIOS) {
      nearest = await _findNearestStation(s);
      if (nearest != null) {
        // If nearest station is > 50km away, mark as outside coverage
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, nearest.lat, nearest.lng);
          if (dist > 50000) outside = true;
        }
      }
    }

    setState(() {
      _stations = s;
      _nearStation = nearest;
      _favorites = favs;
      _isOutsideCoverage = outside;
    });
  }

  Future<Station?> _findNearestStation(List<Station> stations) async {
    try {
      // Check / request permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (e) {
        pos = await Geolocator.getLastKnownPosition();
        if (pos == null) return null;
      }

      Station? closest;
      double minDist = double.infinity;
      for (final st in stations) {
        final d = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, st.lat, st.lng);
        if (d < minDist) {
          minDist = d;
          closest = st;
        }
      }
      return closest;
    } catch (_) {
      return null; // GPS unavailable — fall back to first station
    }
  }

  void _calculateAndNavigate(Station dest) {
    if (_stations.isEmpty) return;
    
    if (_nearStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to find your location. Please check GPS and try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final startId = _nearStation!.id;
    final engine = PathfindingEngine(_stations);
    
    final fastestPath = engine.getShortestPath(startId, dest.id, pref: RoutePreference.fastest);
    final fewestTransfersPath = engine.getShortestPath(startId, dest.id, pref: RoutePreference.fewestTransfers);

    List<RouteOption> options = [];
    if (fastestPath.isNotEmpty) {
      options.add(RouteOption(stations: fastestPath, pref: RoutePreference.fastest, title: "FASTEST"));
    }
    
    if (fewestTransfersPath.isNotEmpty) {
      bool isDifferent = true;
      if (fastestPath.length == fewestTransfersPath.length) {
        bool match = true;
        for (int i = 0; i < fastestPath.length; i++) {
          if (fastestPath[i].id != fewestTransfersPath[i].id) {
            match = false;
            break;
          }
        }
        if (match) isDifferent = false;
      }
      if (isDifferent) {
        options.add(RouteOption(stations: fewestTransfersPath, pref: RoutePreference.fewestTransfers, title: "FEWER CHANGES"));
      }
    }

    if (options.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RouteSelectionScreen(destination: dest, options: options),
        ),
      );
    }
  }



  // ── Dest picker ─────────────────────────────────────
  void _showDestPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Station? selected = _dest;
        final ctrl = TextEditingController();
        List<Station> filtered = List.from(_stations);
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(height: MediaQuery.of(context).size.height * 0.65, child: Column(children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child:
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.07),
                    hintText: 'Search station…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  onChanged: (q) => setSt(() {
                    filtered = _stations.where((s) => s.name.toLowerCase().contains(q.toLowerCase())).toList();
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final s = filtered[i];
                  return ListTile(
                    leading: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: lineColor(s.line))),
                    title: Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    trailing: Text(s.line, style: TextStyle(color: lineColor(s.line), fontSize: 12, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _dest = s);
                      _calculateAndNavigate(s);
                    },
                  );
                },
              )),
            ])),
          );
        });
      },
    );
  }

  Widget _pill(IconData icon, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30), border: Border.all(color: fg.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: fg, size: 15),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.amber),
                title: const Text('Custom Alarm Sound', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Overrides default metro chimes', style: TextStyle(color: Colors.white54)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
                    if (result != null && result.files.single.path != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('custom_alarm_path', result.files.single.path!);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom alarm sound set successfully!')));
                      }
                    }
                  } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.redAccent),
                title: const Text('Reset Alarm Sound', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('custom_alarm_path');
                   if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Using default Metro chimes.')));
                   }
                },
              ),
            ],
          ),
        );
      }
    );
  }

  // ═══════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting + near station
              if (_nearStation != null) ...[
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: lineColor(_nearStation!.line))),
                    const SizedBox(width: 8),
                    Text('Near ${_nearStation!.name}', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.white38, size: 18),
                      tooltip: 'Refresh GPS',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Locating nearest station...')));
                        _loadStations();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Where are you\ngoing today?', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1)),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white54),
                    onPressed: _showSettings,
                  ),
                ],
              ),
              
              if (_isOutsideCoverage) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Colors.orange.shade900.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade900, width: 1)),
                  child: const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                    SizedBox(width: 12),
                    Expanded(child: Text("You appear to be outside the metro coverage area.", style: TextStyle(color: Colors.orange, fontSize: 14, height: 1.3))),
                  ]),
                )
              ],
              
              const SizedBox(height: 32),

              // Destination selector
              GestureDetector(
                onTap: _showDestPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(children: [
                    Icon(Icons.search_rounded, color: Colors.white38, size: 28),
                    SizedBox(width: 16),
                    Expanded(child: Text('Select destination…', style: TextStyle(color: Colors.white38, fontSize: 20))),
                    Icon(Icons.keyboard_arrow_down, color: Colors.white24),
                  ]),
                ),
              ),
              
              const SizedBox(height: 48),

              // "Favorites / Quick Start"
              if (_favorites.isNotEmpty) ...[
                const Text('QUICK START', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 16),
                ..._favorites.map((f) {
                  final destId = f['destinationStationId'] as String;
                  final destSt = _stations.firstWhere((s) => s.id == destId, orElse: () => _stations.first);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FutureBuilder<Station?>(
                      future: DatabaseHelper.instance.getStationById(f['startStationId'] as String),
                      builder: (context, snapshot) {
                        final startSt = snapshot.data;
                        final title = destSt.name;
                        final subtitle = startSt != null ? 'From ${startSt.name}' : '${destSt.line} Line';
                        return GestureDetector(
                          onTap: () {
                            if (startSt != null) {
                              final oldNear = _nearStation;
                              _nearStation = startSt;
                              _calculateAndNavigate(destSt);
                              _nearStation = oldNear;
                            } else {
                              _calculateAndNavigate(destSt);
                            }
                          },
                          onLongPress: () async {
                              bool? del = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E1E28),
                                  title: const Text('Remove Favorite?', style: TextStyle(color: Colors.white)),
                                  content: Text('Remove $title from quick start?', style: const TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true), 
                                      child: const Text('Remove', style: TextStyle(color: Colors.redAccent))
                                    ),
                                  ]
                                )
                              );
                              if (del == true) {
                                await DatabaseHelper.instance.removeFavorite(f['startStationId'] as String, destId);
                                _loadStations();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Favorite removed')));
                                }
                              }
                          },
                          child: _quickStartCard(Icons.star, title, subtitle),
                        );
                      }
                    ),
                  );
                }),
              ],
              
              const Spacer(),

              // Offline Map Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OfflineMapScreen()),
                    );
                  },
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('View Offline Metro Map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickStartCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios, color: Colors.white12, size: 16),
        ],
      ),
    );
  }
}
