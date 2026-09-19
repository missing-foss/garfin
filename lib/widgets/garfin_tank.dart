// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_info.dart';

/// Brand tokens, from `BRANDING.md` § Colours.
///
/// Copied rather than imported because nothing else in `lib/` needs them yet
/// and a palette file with one consumer is a file to keep in step for no
/// reason. If a second screen wants them, that is the moment to lift them out.
const _deep = Color(0xFF2B2035);
const _squid = Color(0xFF241C36);
const _pearl = Color(0xFFEADDFF);
const _lilac = Color(0xFFB69DF8);
const _foam = Color(0xFFF6F2FA);

/// How long the fish takes to close **half** the gap to the finger.
///
/// A half-life rather than a per-second fraction, because the per-second form
/// said nothing about the thing that is actually felt. The old `0.92` sounds
/// nearly instant and is not: it leaves `0.08` of the gap after a whole
/// second, which is 11% of it closed in the first 100ms. Reported, fairly, as
/// the fish being hard to move.
///
/// 45ms closes about 79% in that same 100ms. It still trails — that lag is the
/// character of the thing and a fish welded to the fingertip is not a fish —
/// but it now answers the hand rather than arguing with it.
///
/// Frame-rate independent, applied as `1 - pow(0.5, dt / halfLife)`, so a slow
/// frame moves further rather than the fish moving more slowly on a slower
/// device.
const _followHalfLife = 0.045;

/// The player's radius at the start, and the range it may reach.
const _startRadius = 26.0;
const _minRadius = 12.0;
const _maxRadius = 90.0;

/// Roughly the share of new circles that the fish can eat **at the size it is
/// now**.
///
/// The whole of the tuning is in that last clause. Drawn from a fixed range
/// instead, as this was, the tank contradicts itself at both ends: at the
/// starting radius of 26 only 39% of a uniform 8..54 draw is edible, which is
/// about five circles of fourteen and the thin opening that was reported —
/// while above radius 54 *nothing that can exist* is bigger than the fish, so
/// the one rule stops applying and the screen becomes a fish eating everything
/// it touches. Measured, not reasoned about; the first read of this went the
/// wrong way.
///
/// Relative, both ends stay true for the whole of the play: something is
/// always worth chasing, and something is always worth avoiding.
const _edibleShare = 0.62;

/// How far a circle's radius may sit either side of the player's.
///
/// The gaps at 0.90 and 1.12 are deliberate: a circle within a few per cent of
/// the fish is a coin toss the player cannot see coming, and the rule is only
/// legible if which one it is can be read off the screen.
const _edibleRange = (0.28, 0.90);
const _threatRange = (1.12, 2.20);

/// Absolute bounds, so the relative draw cannot produce a speck or a wall.
const _minDrifterRadius = 6.0;
const _maxDrifterRadius = 96.0;

/// How many drifting circles the tank keeps.
const _drifterCount = 14;

/// One drifting circle.
///
/// Public alongside [GarfinTankState] so a test can build a world of exactly
/// one known circle. The acceptance for this screen is "eat something smaller,
/// bounce off something bigger", and asserting that against a randomly
/// populated tank would be asserting about whatever the seed happened to put
/// in the way.
class TankDrifter {
  TankDrifter({
    required this.position,
    required this.velocity,
    required this.radius,
    required this.colour,
  });

  Offset position;
  Offset velocity;
  double radius;
  Color colour;
}

/// The egg: a tank, a fish, and one rule nobody states.
///
/// Touch something smaller and you eat it and grow; touch something bigger and
/// you bounce off it and shrink. That is the app's own subject with the words
/// taken out — what is out of reach stops being out of reach as you grow.
///
/// **No text, anywhere, deliberately.** The score is the size of the fish: you
/// see how you are doing by looking at yourself. That is what gives this zero
/// l10n surface — nothing here can fail the hardcoded-string check or either
/// translation gate, because there is nothing to translate. A fail state would
/// need a way to restart, a restart usually wants a word, and one word drags
/// the whole apparatus into an Easter egg. Having no way to lose removes it.
///
/// **Nothing is persisted and nothing is sent.** No high score, no "seen it"
/// flag, no preference. It exists while the screen is open and is then gone.
class GarfinTank extends StatefulWidget {
  const GarfinTank({super.key, this.seed});

  /// Fixed in tests so the world is deterministic; null uses a real one.
  final int? seed;

  @override
  State<GarfinTank> createState() => GarfinTankState();
}

/// Public so a test can read the world it is asserting about.
class GarfinTankState extends State<GarfinTank>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Random _random;

  final List<TankDrifter> drifters = <TankDrifter>[];

  Offset player = Offset.zero;
  Offset _target = Offset.zero;
  double playerRadius = _startRadius;

  /// The mark is drawn facing right, so swimming left is a mirror.
  bool facingLeft = false;

  Size _tank = Size.zero;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _random = Random(widget.seed);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _sizeTo(Size size) {
    if (size == _tank) return;
    final first = _tank == Size.zero;
    _tank = size;
    if (!first) return;
    player = size.center(Offset.zero);
    _target = player;
    for (var i = 0; i < _drifterCount; i++) {
      drifters.add(spawn());
    }
  }

  /// A circle somewhere in the tank, sized against the fish **as it is now**.
  ///
  /// Public for the same reason [TankDrifter] is: the property worth testing is
  /// a distribution, and a test that had to reach it by playing the game would
  /// be asserting about whatever the seed put in the way. See [_edibleShare].
  TankDrifter spawn({double? atX}) {
    final (lo, hi) = _random.nextDouble() < _edibleShare
        ? _edibleRange
        : _threatRange;
    final radius = playerRadius * (lo + _random.nextDouble() * (hi - lo));
    return TankDrifter(
      position: Offset(
        atX ?? _random.nextDouble() * _tank.width,
        _random.nextDouble() * _tank.height,
      ),
      velocity: Offset(
        (_random.nextDouble() - 0.5) * 40,
        (_random.nextDouble() - 0.5) * 40,
      ),
      radius: radius.clamp(_minDrifterRadius, _maxDrifterRadius),
      colour: [_pearl, _lilac, _foam][_random.nextInt(3)],
    );
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_tank == Size.zero || dt <= 0) return;
    setState(() => _advance(dt.clamp(0.0, 0.05)));
  }

  void _advance(double dt) {
    // Frame-rate independent easing towards the finger.
    final k = 1 - pow(0.5, dt / _followHalfLife).toDouble();
    final next = player + (_target - player) * k;
    if ((next.dx - player.dx).abs() > 0.05) facingLeft = next.dx < player.dx;
    player = next;

    for (final drifter in drifters) {
      drifter.position += drifter.velocity * dt;
      // Wrapping rather than bouncing: a tank whose edges push back reads as
      // walls, and there is nothing to be trapped against here.
      if (drifter.position.dx < -drifter.radius) {
        drifter.position = Offset(
          _tank.width + drifter.radius,
          drifter.position.dy,
        );
      }
      if (drifter.position.dx > _tank.width + drifter.radius) {
        drifter.position = Offset(-drifter.radius, drifter.position.dy);
      }
      if (drifter.position.dy < -drifter.radius) {
        drifter.position = Offset(
          drifter.position.dx,
          _tank.height + drifter.radius,
        );
      }
      if (drifter.position.dy > _tank.height + drifter.radius) {
        drifter.position = Offset(drifter.position.dx, -drifter.radius);
      }
    }

    _resolveTouches();
  }

  /// The one rule, applied. Nothing here can end the game.
  void _resolveTouches() {
    for (var i = drifters.length - 1; i >= 0; i--) {
      final drifter = drifters[i];
      final gap = (drifter.position - player).distance;
      if (gap > playerRadius + drifter.radius) continue;

      if (drifter.radius < playerRadius) {
        // Eaten. Growth tapers so the tank does not become trivial in ten
        // seconds, and is capped so the fish cannot outgrow its own water.
        playerRadius = min(_maxRadius, playerRadius + drifter.radius * 0.12);
        drifters[i] = spawn(atX: _random.nextBool() ? -40 : _tank.width + 40);
      } else {
        // Bounced. Shrinking is the only penalty and it is recoverable —
        // floored rather than allowed to reach nothing, because a fish that
        // vanished would be a fail state by another name.
        playerRadius = max(_minRadius, playerRadius - drifter.radius * 0.06);
        final away = gap == 0
            ? const Offset(1, 0)
            : (player - drifter.position) / gap;
        player += away * (playerRadius + drifter.radius - gap + 8);
        _target = player;
      }
    }
  }

  void _moveTo(Offset local) => _target = local;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deep,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _moveTo(d.localPosition),
        onPanUpdate: (d) => _moveTo(d.localPosition),
        onTapDown: (d) => _moveTo(d.localPosition),
        // A swipe down leaves, as well as the system back gesture. No button,
        // because a button needs a label.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 600) Navigator.of(context).maybePop();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            _sizeTo(constraints.biggest);
            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_deep, _squid],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _TankPainter(drifters)),
                  ),
                  Positioned(
                    left: player.dx - playerRadius,
                    top: player.dy - playerRadius,
                    width: playerRadius * 2,
                    height: playerRadius * 2,
                    child: Transform.flip(
                      flipX: facingLeft,
                      child: Image.asset(
                        'assets/brand/garfin-mark.png',
                        // The product name, not a sentence: this is the one
                        // string in here and it is a proper noun, so it is
                        // neither translated nor a UI string.
                        semanticLabel: appClientName,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TankPainter extends CustomPainter {
  _TankPainter(this.drifters);

  final List<TankDrifter> drifters;

  @override
  void paint(Canvas canvas, Size size) {
    for (final drifter in drifters) {
      canvas.drawCircle(
        drifter.position,
        drifter.radius,
        Paint()..color = drifter.colour.withValues(alpha: 0.55),
      );
    }
  }

  // The world changes every tick; the widget rebuilds with it.
  @override
  bool shouldRepaint(covariant _TankPainter oldDelegate) => true;
}
