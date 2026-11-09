import 'package:flutter/material.dart';

import 'settings.dart';
import 'tracker.dart';
import 'tv.dart' show isTv;
import 'ui.dart' show scheme, seed;

/// Shown once per launch: set when the greeting has run, so a rebuilt app (a layout change) doesn't greet again.
bool _greeted = false;

/// Clean, smooth ANIZEN startup animation over [child] when the app opens, while [child] loads underneath.
/// Off in Settings → Appearance.
class Welcome extends StatefulWidget {
  const Welcome({super.key, required this.child});

  final Widget child;

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> with SingleTickerProviderStateMixin {
  final bool _showing = !_greeted && Settings.welcome;
  late final _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// The last name the account answered with, so the greeting never waits on the network; refreshed for next time.
  String? _name = Tracker.signedIn ? Settings.welcomeName : null;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _greeted = true;
    if (!_showing) {
      _run.value = 1; // nothing to play: the app sits at its resting scale
      return;
    }
    _run.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
    if (Tracker.signedIn) {
      Tracker.viewer()
          .then((me) {
            final name = me?['name'] as String?;
            if (name == null) return;
            Settings.welcomeName = name;
            // Only before the greeting has shown a name: never swap it mid-read.
            if (mounted && _name == null && _run.value < .3) {
              setState(() => _name = name);
            }
          })
          .catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  /// [_run] between [begin] and [end] (fractions of it), eased.
  Animation<double> _step(
    double begin,
    double end, [
    Curve curve = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _run,
    curve: Interval(begin, end, curve: curve),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = isTv
        ? 480.0
        : (MediaQuery.sizeOf(context).width * .65).clamp(180.0, 280.0);
    final logo = Image.asset(
      scheme.brightness == Brightness.light
          ? 'assets/icon/aniview_wordmark_light.png'
          : 'assets/icon/aniview_wordmark.png',
      width: width,
      fit: BoxFit.contain,
      semanticLabel: 'ANIZEN',
    );
    final markFade = _step(0, .45, Curves.easeOut);
    final markScale = _step(0, .55, Curves.easeOutCubic);
    final glowFade = _step(.1, .6, Curves.easeInOut);
    final greeting = _step(.45, .8);
    final out = _step(.82, 1, Curves.easeIn);

    // Always this Stack, so [child] keeps its place (and its state) when the greeting goes.
    return Stack(
      children: [
        // Settles from a touch larger as the splash fades, so the app arrives rather than being uncovered.
        ScaleTransition(
          scale: Tween(begin: 1.02, end: 1.0).animate(out),
          child: widget.child,
        ),
        // Lets go of taps and the remote as it fades, so nothing waits on it.
        if (_showing && !_done)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: ReverseAnimation(out),
                child: Material(
                  color: scheme.surface,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The brand's cyan, softly behind the mark.
                      FadeTransition(
                        opacity: glowFade,
                        child: Container(
                          width: width * 1.6,
                          height: width * 1.6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                seed.withValues(alpha: .18),
                                seed.withValues(alpha: 0),
                              ],
                              stops: const [0, .65],
                            ),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Clean, centered ANIZEN logo presentation with smooth scale and fade
                          FadeTransition(
                            opacity: markFade,
                            child: ScaleTransition(
                              scale: Tween(
                                begin: .90,
                                end: 1.0,
                              ).animate(markScale),
                              child: logo,
                            ),
                          ),
                          SizedBox(height: isTv ? 28 : 20),
                          FadeTransition(
                            opacity: greeting,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, .25),
                                end: Offset.zero,
                              ).animate(greeting),
                              child: Text(
                                _name == null
                                    ? 'Welcome back'
                                    : 'Welcome back, $_name',
                                textAlign: TextAlign.center,
                                style:
                                    (isTv
                                            ? text.headlineSmall
                                            : text.titleMedium)
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
