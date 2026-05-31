import 'dart:async';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../services/pathfinding_engine.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  
  // Staggered animations
  late Animation<double> _drawLineRed;
  late Animation<double> _drawLineBlue;
  late Animation<double> _drawLineGreen;
  late Animation<double> _trainProgress;
  late Animation<double> _textFade;
  late Animation<double> _textSlide;

  // Wait for both animation to finish AND db to load
  bool _dbLoaded = false;
  bool _animFinished = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 4500),
    );

    // 1. Draw Red Line (0.0 to 0.2)
    _drawLineRed = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.2, curve: Curves.easeOut)),
    );
    // 2. Draw Blue Line (0.2 to 0.4)
    _drawLineBlue = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.4, curve: Curves.easeOut)),
    );
    // 3. Draw Green Line (0.4 to 0.6)
    _drawLineGreen = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.6, curve: Curves.easeOut)),
    );
    // 4. Train moves across the lines (0.2 to 0.7)
    _trainProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.7, curve: Curves.easeInOut)),
    );
    // 5. Text fades and slides up (0.6 to 1.0)
    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );
    _textSlide = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOutCubic)),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Hold on splash 1 extra second so logo is visible
        Future.delayed(const Duration(milliseconds: 1000), () {
          _animFinished = true;
          _checkAndNavigate();
        });
      }
    });

    _ctrl.forward();
    _loadDatabase();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadDatabase() async {
    final s = await DatabaseHelper.instance.getAllStations();
    if (s.isNotEmpty) {
      // Warm up the graph in memory during the animation
      PathfindingEngine(s);
    }
    _dbLoaded = true;
    _checkAndNavigate();
  }

  void _checkAndNavigate() {
    if (_dbLoaded && _animFinished && mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          transitionDuration: const Duration(milliseconds: 1200),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The Graphic
                SizedBox(
                  width: 200,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Base track lines (faded)
                      Container(margin: const EdgeInsets.only(left: 10, top: 28), width: 180, height: 4, color: Colors.white10),
                      
                      // Colored Lines drawing in
                      Positioned(
                        left: 10, top: 28,
                        child: Row(
                          children: [
                            Container(width: 60 * _drawLineRed.value, height: 4, color: const Color(0xFFE53935)),
                            Container(width: 60 * _drawLineBlue.value, height: 4, color: const Color(0xFF1E88E5)),
                            Container(width: 60 * _drawLineGreen.value, height: 4, color: const Color(0xFF43A047)),
                          ],
                        ),
                      ),

                      // Station Nodes (pop in as line reaches them)
                      Positioned(left: 0, top: 20, child: _node(const Color(0xFFE53935), _drawLineRed.value > 0)),
                      Positioned(left: 60, top: 20, child: _node(const Color(0xFF1E88E5), _drawLineBlue.value > 0)),
                      Positioned(left: 120, top: 20, child: _node(const Color(0xFF43A047), _drawLineGreen.value > 0)),
                      Positioned(left: 180, top: 20, child: _node(Colors.white, _drawLineGreen.value == 1.0)),

                      // The "Train" moving
                      if (_trainProgress.value > 0 && _trainProgress.value <= 1.0)
                        Positioned(
                          left: 10 + (160 * _trainProgress.value),
                          top: 16,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: const Icon(Icons.train, color: Colors.black, size: 16),
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // The Text
                Opacity(
                  opacity: _textFade.value,
                  child: Transform.translate(
                    offset: Offset(0, _textSlide.value),
                    child: Column(
                      children: [
                        const Text(
                          'METRO WAKE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Route & Sleep. We handle the rest.',
                          style: TextStyle(
                            color: Colors.blueAccent.shade100,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _node(Color color, bool show) {
    if (!show) return const SizedBox(width: 20, height: 20);
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        border: Border.all(color: color, width: 4),
        shape: BoxShape.circle,
      ),
    );
  }
}
