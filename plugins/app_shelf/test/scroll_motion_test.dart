// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:app_shelf/src/scroll_motion.dart';
import 'package:app_shelf/src/entry_retention.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final forward = ScrollMotion(
    start: 20,
    velocity: 0,
    target: 140,
    minimum: 0,
    maximum: 500,
  );
  var last = forward.position(0);
  for (var frame = 1; frame <= 240; frame++) {
    final next = forward.position(frame / 240);
    check(
      next >= last && next <= 140,
      'forward scroll must be continuous and monotonic',
    );
    last = next;
  }
  check(forward.done(1) && (last - 140).abs() < 0.1, 'scroll did not settle');
  final reverse = ScrollMotion(
    start: forward.position(0.05),
    velocity: forward.speed(0.05),
    target: 0,
    minimum: 0,
    maximum: 500,
  );
  check(reverse.position(0) == forward.position(0.05), 'retarget jumped');
  check(reverse.speed(0) == forward.speed(0.05), 'retarget lost velocity');
  check(reverse.done(2), 'reverse did not settle');
  for (var frame = 0; frame <= 480; frame++) {
    check(
      reverse.position(frame / 240) >= 0 &&
          reverse.position(frame / 240) <= 500,
      'reversal escaped viewport',
    );
  }
  check(
    scrollTarget(
          pixels: 30,
          pending: 120,
          delta: 40,
          previousDirection: 1,
          minimum: 0,
          maximum: 500,
        ) ==
        160,
    'continuous input lost distance',
  );
  check(
    scrollTarget(
          pixels: 30,
          pending: 120,
          delta: -20,
          previousDirection: 1,
          minimum: 0,
          maximum: 500,
        ) ==
        10,
    'reversing kept stale pending distance',
  );
  check(
    scrollTarget(
          pixels: 490,
          pending: 490,
          delta: 100,
          previousDirection: 1,
          minimum: 0,
          maximum: 500,
        ) ==
        500,
    'bottom edge overflow',
  );
  final slower = ScrollMotion(
    start: 20,
    velocity: 0,
    target: 140,
    minimum: 0,
    maximum: 500,
    scale: 2,
  );
  check(
    (slower.position(0.2) - forward.position(0.1)).abs() < 0.000001,
    'duration setting did not scale motion',
  );

  final pool = EntryRetention(2);
  var evictions = 0;
  final first = pool.acquire('a', () => evictions++);
  final second = pool.acquire('b', () => evictions++);
  final third = pool.acquire('c', () => evictions++);
  check(
    !first.retained &&
        second.retained &&
        third.retained &&
        pool.length == 2 &&
        evictions == 1,
    'retention exceeded budget',
  );
  final replacement = pool.acquire('b', () => evictions++);
  pool.release(second);
  check(
    replacement.retained && pool.length == 2,
    'stale release removed replacement',
  );
  pool.release(third);
  pool.release(replacement);
  check(pool.length == 0, 'disposed entries were retained');
  stdout.writeln(
    'PASS: continuous wheel targets, reversal velocity, boundaries, motion scale and bounded row leases.',
  );
}
