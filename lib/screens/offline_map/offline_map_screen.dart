import 'package:flutter/material.dart';
import '../../data/database_helper.dart';
import '../../models/station.dart';

class OfflineMapScreen extends StatefulWidget {
  const OfflineMapScreen({super.key});

  @override
  State<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends State<OfflineMapScreen> {
  List<Station> _stations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DatabaseHelper.instance.getAllStations();
    // Sort each line by orderIndex
    s.sort((a, b) {
      int lineCmp = a.line.compareTo(b.line);
      if (lineCmp != 0) return lineCmp;
      return a.orderIndex.compareTo(b.orderIndex);
    });
    setState(() { _stations = s; _loading = false; });
  }

  Color _lineColor(String line) {
    if (line == 'Red')   return const Color(0xFFE53935);
    if (line == 'Blue')  return const Color(0xFF1E88E5);
    return const Color(0xFF43A047);
  }

  @override
  Widget build(BuildContext context) {
    final lines = ['Red', 'Blue', 'Green'];
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        title: const Text('Metro System Map',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0D0D14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Legend
                  Wrap(spacing: 16, runSpacing: 8, children: lines.map((l) =>
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 24, height: 6, decoration: BoxDecoration(
                        color: _lineColor(l), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Text('$l Line', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ])).toList()),
                  const SizedBox(height: 24),

                  // One column per metro line
                  ...lines.map((line) {
                    final stns = _stations.where((s) => s.line == line).toList();
                    final color = _lineColor(line);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            Container(width: 12, height: 12, decoration: BoxDecoration(
                                shape: BoxShape.circle, color: color)),
                            const SizedBox(width: 8),
                            Text('$line Line  •  ${stns.length} stations',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                          ]),
                        ),
                        const SizedBox(height: 12),

                        // Stations
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The vertical track line
                              Column(children: [
                                const SizedBox(height: 8),
                                Expanded(child: Container(width: 3,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [color, color.withOpacity(0.3)],
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ))),
                              ]),
                              const SizedBox(width: 12),
                              // Station list
                              Expanded(
                                child: Column(
                                  children: stns.asMap().entries.map((e) {
                                    final idx = e.key;
                                    final s = e.value;
                                    final isFirst = idx == 0;
                                    final isLast = idx == stns.length - 1;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(children: [
                                        // Dot
                                        Container(
                                          width: isFirst || isLast ? 14 : 10,
                                          height: isFirst || isLast ? 14 : 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isFirst || isLast ? color : Colors.white,
                                            border: Border.all(color: color, width: 2),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        // Station name
                                        Expanded(child: Text(
                                          s.name,
                                          style: TextStyle(
                                            color: isFirst || isLast ? Colors.white : Colors.white70,
                                            fontSize: isFirst || isLast ? 14 : 13,
                                            fontWeight: isFirst || isLast ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        )),
                                        // Station number
                                        Text('${s.orderIndex}',
                                            style: TextStyle(color: color.withOpacity(0.6), fontSize: 11)),
                                      ]),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
