import 'dart:io';

import 'package:denial_taskbar_custom/src/volume_presentation.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final volume = VolumePresentation();
  check(
    volume.level == null,
    'Opening must show unknown until native state arrives, never a 46% placeholder.',
  );
  final initialRead = volume.beginRead();
  volume.nativeState(0, isMuted: false);
  volume.completeRead(initialRead, 0.46);
  check(
    volume.level == 0,
    'A delayed initial result cannot replace newer native zero volume.',
  );

  final mutedRead = volume.beginRead();
  volume.nativeState(0.46, isMuted: true);
  volume.completeRead(mutedRead, 0.46);
  check(
    volume.level == 0 && volume.muted,
    'Read futures must not lose the native mute flag.',
  );

  final staleRead = volume.beginRead();
  volume.beginInteraction();
  volume.intent(0.75);
  volume.completeRead(staleRead, 0);
  volume.nativeState(0.3, isMuted: false);
  check(
    volume.level == 0.75,
    'Native updates during a drag cannot rewind the thumb.',
  );
  volume.commit(0.75);
  volume.nativeState(0.3, isMuted: false);
  check(
    volume.level == 0.75 && volume.needsReconciliation,
    'Late coalesced acknowledgements must not replace the latest intent.',
  );
  volume.nativeState(0.75, isMuted: false);
  check(
    volume.level == 0.75 && !volume.needsReconciliation,
    'Matching native acknowledgement must settle the optimistic presentation.',
  );

  volume.commit(0.8);
  volume.nativeState(0, isMuted: false);
  volume.reconcile();
  final reconciliation = volume.beginRead();
  volume.nativeState(0, isMuted: true);
  volume.completeRead(reconciliation, 0);
  check(
    volume.level == 0 && volume.muted && !volume.needsReconciliation,
    'Reconciliation must restore actual volume when a write was rejected.',
  );
  final unavailable = VolumePresentation();
  unavailable.completeRead(unavailable.beginRead(), null);
  check(
    unavailable.level == null,
    'Unavailable reads must remain unknown instead of inventing a value.',
  );
  unavailable.completeRead(unavailable.beginRead(), 1.4);
  check(
    unavailable.level == 1,
    'Native levels must stay within slider bounds.',
  );
  stdout.writeln(
    'Volume initialization, mute, drag and stale-reply regression checks passed.',
  );
}
