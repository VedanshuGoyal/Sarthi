import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../core/brand/mojud_logo.dart';

/// The MOJUD launch screen, shown while the saved session is read back out of
/// secure storage on cold start.
///
/// It is deliberately the same composition as the native launch screens
/// (`launch_background.xml` on Android, `LaunchImage` on iOS): the stacked
/// lockup, centred, on the Deep Signal canvas. The native screen hands over to
/// this one the moment Flutter draws its first frame, so the handover reads as
/// one continuous screen rather than a flash of a second one.
///
/// This is a pure view — it owns no session logic and decides nothing about
/// where the app goes next. [_AppRoot] in `main.dart` swaps it out when the
/// session resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = DeepSignalTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Size the lockup off the smaller axis so it stays balanced from a
            // small phone through to a tablet in landscape, rather than
            // ballooning on wide windows.
            final shortestSide = constraints.biggest.shortestSide;
            final markHeight = (shortestSide * 0.17).clamp(44.0, 104.0);

            return Stack(
              children: [
                Center(
                  child: _EntranceFade(
                    child: MojudLockup(
                      markHeight: markHeight,
                      orientation: MojudLockupOrientation.stacked,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      bottom: DeepSignalTokens.s34,
                      left: DeepSignalTokens.s34,
                      right: DeepSignalTokens.s34,
                    ),
                    child: _SignalBar(
                      track: tokens.hairline,
                      signal: tokens.accent,
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
}

/// Fades and lifts the lockup in once, on the Deep Signal timing.
class _EntranceFade extends StatefulWidget {
  const _EntranceFade({required this.child});

  final Widget child;

  @override
  State<_EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<_EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DeepSignalTokens.motion,
  )..forward();

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: DeepSignalTokens.easing,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "reduce motion" setting — the mark still appears, it just
    // does not travel.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return FadeTransition(
      opacity: _curve,
      child: reduceMotion
          ? widget.child
          : SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(_curve),
              child: widget.child,
            ),
    );
  }
}

/// A 1px hairline with a single accent segment sweeping along it — the Deep
/// Signal reading of a progress indicator. No spinner, no fill.
class _SignalBar extends StatefulWidget {
  const _SignalBar({required this.track, required this.signal});

  final Color track;
  final Color signal;

  @override
  State<_SignalBar> createState() => _SignalBarState();
}

class _SignalBarState extends State<_SignalBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With reduce-motion on, hold a static hairline rather than sweeping.
    if (MediaQuery.disableAnimationsOf(context)) {
      return SizedBox(height: 1, child: ColoredBox(color: widget.track));
    }

    return SizedBox(
      height: 1,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _SignalBarPainter(
            progress: _controller.value,
            track: widget.track,
            signal: widget.signal,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SignalBarPainter extends CustomPainter {
  const _SignalBarPainter({
    required this.progress,
    required this.track,
    required this.signal,
  });

  final double progress;
  final Color track;
  final Color signal;

  /// The sweeping segment's length, as a fraction of the bar.
  static const double _segment = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);

    // Ease the segment so it slows at each end instead of scrolling linearly.
    final eased = DeepSignalTokens.easing.transform(progress);
    final start = (eased * (1 + _segment) - _segment) * size.width;
    final left = start.clamp(0.0, size.width);
    final right = (start + _segment * size.width).clamp(0.0, size.width);
    if (right <= left) return;

    canvas.drawRect(
      Rect.fromLTRB(left, 0, right, size.height),
      Paint()..color = signal,
    );
  }

  @override
  bool shouldRepaint(_SignalBarPainter old) =>
      old.progress != progress || old.track != track || old.signal != signal;
}
