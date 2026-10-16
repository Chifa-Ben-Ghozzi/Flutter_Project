import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n.dart';

/// Shows an animated splash, runs [init] in parallel (e.g. Api.init),
/// then fades into [next] (your current home widget).
class SplashScreen extends StatefulWidget {
  final Widget next;
  final Future<void> Function()? init;
  const SplashScreen({super.key, required this.next, this.init});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final Animation<double> logo =
      CurvedAnimation(parent: c, curve: const Interval(0.0, 0.45, curve: Curves.elasticOut));
  late final Animation<double> car =
      CurvedAnimation(parent: c, curve: const Interval(0.15, 0.5, curve: Curves.easeOutCubic));
  late final Animation<double> title =
      CurvedAnimation(parent: c, curve: const Interval(0.5, 0.75, curve: Curves.easeOut));
  late final Animation<double> sub =
      CurvedAnimation(parent: c, curve: const Interval(0.65, 0.9, curve: Curves.easeOut));

  bool done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await Future.wait<void>([
        c.forward(),
        widget.init?.call() ?? Future<void>.value(),
      ]);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => done = true);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Widget _splash() {
    return Scaffold(
      key: const ValueKey('splash'),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3F51B5), Color(0xFF1A237E)],
          ),
        ),
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                scale: logo.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Transform.translate(
                      offset: Offset((1 - car.value) * -90, 0),
                      child: Opacity(
                        opacity: car.value.clamp(0.0, 1.0),
                        child: const Icon(Icons.directions_car_rounded, size: 60, color: Color(0xFF3F51B5)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: title.value,
                child: Transform.translate(
                  offset: Offset(0, (1 - title.value) * 20),
                  child: const Text(
                    'Campus Carpool',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: sub.value,
                child: Text(
                  context.tr('tagline'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(height: 40),
              Opacity(
                opacity: sub.value,
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: c.value,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: done ? KeyedSubtree(key: const ValueKey('next'), child: widget.next) : _splash(),
    );
  }
}