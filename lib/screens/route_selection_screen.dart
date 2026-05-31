import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/station.dart';
import '../models/route_option.dart';
import '../data/database_helper.dart';
import 'live_journey_screen.dart';

class RouteSelectionScreen extends StatefulWidget {
  final Station destination;
  final List<RouteOption> options;

  const RouteSelectionScreen({
    super.key,
    required this.destination,
    required this.options,
  });

  @override
  State<RouteSelectionScreen> createState() => _RouteSelectionScreenState();
}

class _RouteSelectionScreenState extends State<RouteSelectionScreen> {
  int _selectedRouteIdx = 0;

  void _startJourney(BuildContext context, Color destColor) async {
    final route = widget.options[_selectedRouteIdx];
    final startStation = route.stations.first;
    
    // Check Distance
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, startStation.lat, startStation.lng);
        if (dist > 2000) { // > 2km away
          bool? proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E28),
              title: const Text('Start Journey?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text('You are ${(dist/1000).toStringAsFixed(1)}km away from ${startStation.name}. Live tracking may not work accurately until you board the train. Start anyway?', 
                style: const TextStyle(color: Colors.white70, height: 1.4)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: destColor),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Start Anyway', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (proceed != true) return;
        }
      }
    } catch (e) {
       // Ignore permission issues here, LiveTracker handles it
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => LiveJourneyScreen(
          destination: widget.destination,
          route: route,
        ),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destColor = lineColor(widget.destination.line);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Select Route', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.star_outline_rounded),
            tooltip: 'Save to Favorites',
            onPressed: () async {
              final startId = widget.options[_selectedRouteIdx].stations.first.id;
              final destId = widget.destination.id;
              await DatabaseHelper.instance.addFavorite(startId, destId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved route to ${widget.destination.name} as a favorite!'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header showing destination
            Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                border: const Border(bottom: BorderSide(color: Colors.white10)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    destColor.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  const Text('ROUTE TO', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text(widget.destination.name, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1)),
                ],
              ),
            ),

            // Route Cards list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: widget.options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (ctx, i) {
                  final opt = widget.options[i];
                  final isSelected = _selectedRouteIdx == i;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedRouteIdx = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? destColor.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? destColor : Colors.white12,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(opt.title, style: TextStyle(color: isSelected ? destColor : Colors.white54, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                              if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text('${opt.stops}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 8),
                              const Text('stops', style: TextStyle(color: Colors.white54, fontSize: 14)),
                              
                              const SizedBox(width: 24),
                              
                              Text('${opt.transfers}', style: TextStyle(color: opt.transfers == 0 ? Colors.greenAccent : Colors.orangeAccent, fontSize: 28, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 8),
                              const Text('changes', style: TextStyle(color: Colors.white54, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _lineProgressPreview(opt),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Start Journey Button
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
                color: Color(0xFF0D0D14),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _startJourney(context, destColor),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: destColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Start Journey', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineProgressPreview(RouteOption opt) {
    if (opt.stations.isEmpty) return const SizedBox();

    // Build list of key nodes: start, transfer points, destination
    final List<_RouteNode> nodes = [];
    nodes.add(_RouteNode(name: opt.stations.first.name, line: opt.stations.first.line, isTransfer: false));

    String currentLine = opt.stations.first.line;
    for (int i = 1; i < opt.stations.length - 1; i++) {
      if (opt.stations[i].line != currentLine) {
        nodes.add(_RouteNode(name: opt.stations[i].name, line: opt.stations[i].line, isTransfer: true));
        currentLine = opt.stations[i].line;
      }
    }
    nodes.add(_RouteNode(name: opt.stations.last.name, line: opt.stations.last.line, isTransfer: false));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < nodes.length; i++) ...[
            _flowNode(nodes[i], i == 0, i == nodes.length - 1),
            if (i < nodes.length - 1)
              _flowConnector(nodes[i].line),
          ],
        ],
      ),
    );
  }

  Widget _flowNode(_RouteNode node, bool isFirst, bool isLast) {
    final color = lineColor(node.line);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isFirst || isLast ? 14 : 12,
          height: isFirst || isLast ? 14 : 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: isFirst || isLast ? 2 : 1),
            boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)],
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 68,
          child: Text(
            node.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isFirst || isLast ? Colors.white : Colors.white60,
              fontSize: 9,
              fontWeight: isFirst || isLast ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        if (node.isTransfer) ...[
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: lineColor(node.line).withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Transfer',
              style: TextStyle(color: lineColor(node.line), fontSize: 7, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  Widget _flowConnector(String line) {
    return Container(
      width: 28,
      height: 2,
      margin: const EdgeInsets.only(bottom: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [lineColor(line), lineColor(line).withOpacity(0.4)]),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _miniDot(String line) {
    return Container(
      width: 12, height: 12,
      decoration: BoxDecoration(shape: BoxShape.circle, color: lineColor(line)),
    );
  }
}

class _RouteNode {
  final String name;
  final String line;
  final bool isTransfer;
  _RouteNode({required this.name, required this.line, required this.isTransfer});
}
