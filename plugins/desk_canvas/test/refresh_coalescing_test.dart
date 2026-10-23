// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone Dart checks; no Flutter engine, user files, or desktop operations.
import 'dart:async';
import 'dart:io';

import 'package:desk_canvas/src/desktop_store.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> nextTurn() => Future<void>.delayed(Duration.zero);

Future<void> burstAndWaiters() async {
  final gates = List.generate(3, (_) => Completer<void>());
  final snapshots = <int>[];
  var state = 0;
  final queue = DesktopRefreshQueue(() async {
    final index = snapshots.length;
    snapshots.add(state);
    await gates[index].future;
  });
  var firstDone = false;
  final first = queue.refresh().then((_) => firstDone = true);
  state = 1;
  var secondDone = false;
  final burst = List.generate(200, (_) => queue.refresh());
  final second = Future.wait(burst).then((_) => secondDone = true);
  check(snapshots.length == 1, 'An active scan must not run in parallel');
  gates[0].complete();
  await nextTurn();
  check(firstDone, 'The first caller should finish with its own scan');
  check(!secondDone, 'Later callers must wait for a subsequent scan');
  check(snapshots.length == 2, 'A burst must coalesce into one trailing scan');
  state = 2;
  var thirdDone = false;
  final third = queue.refresh().then((_) => thirdDone = true);
  gates[1].complete();
  await nextTurn();
  check(secondDone, 'The burst should finish with the second scan');
  check(!thirdDone, 'Requests during the trailing scan need another scan');
  check(snapshots.length == 3, 'A late state change must not be dropped');
  gates[2].complete();
  await Future.wait([first, second, third]);
  check(snapshots.join(',') == '0,1,2', 'Scans must observe the final state');
  queue.dispose();
}

Future<void> errorsDoNotPoisonQueue() async {
  final firstGate = Completer<void>();
  var scans = 0;
  final queue = DesktopRefreshQueue(() async {
    scans++;
    if (scans == 1) {
      await firstGate.future;
      throw const FileSystemException('Expected scan failure');
    }
  });
  var failed = false;
  final first = queue.refresh().then<void>(
    (_) => throw StateError('The failed scan must report its failure'),
    onError: (Object error) {
      check(error is FileSystemException, 'Preserve the original scan failure');
      failed = true;
    },
  );
  final second = queue.refresh();
  firstGate.complete();
  await Future.wait([first, second]);
  check(failed && scans == 2, 'A pending request must survive a failed scan');
  await queue.refresh();
  check(scans == 3, 'New requests must still work after an earlier failure');
  queue.dispose();

  var synchronousScans = 0;
  final synchronous = DesktopRefreshQueue(() {
    if (++synchronousScans == 1) throw StateError('Synchronous failure');
    return Future.value();
  });
  try {
    await synchronous.refresh();
    throw StateError('Expected synchronous failure');
  } on StateError catch (error) {
    check(error.message == 'Synchronous failure', 'Report synchronous errors');
  }
  await synchronous.refresh();
  check(
    synchronousScans == 2,
    'Synchronous errors must not leave inFlight set',
  );
  synchronous.dispose();
}

Future<void> disposalSkipsPendingScans() async {
  final gate = Completer<void>();
  var scans = 0;
  final queue = DesktopRefreshQueue(() async {
    scans++;
    await gate.future;
  });
  final active = queue.refresh();
  final pending = List.generate(20, (_) => queue.refresh());
  queue.dispose();
  await Future.wait(pending);
  await queue.refresh();
  gate.complete();
  await active;
  check(scans == 1, 'Disposal must cancel pending and future scans');
  queue.dispose();
}

Future<void> realDirectoryFinalState() async {
  final temporary = await Directory.systemTemp.createTemp('desk-refresh-');
  final store = DesktopStore(
    environment: {
      'HOME': temporary.path,
      'XDG_CONFIG_HOME': '${temporary.path}/config',
    },
  );
  try {
    final desktop = await Directory('${temporary.path}/Desktop').create();
    await store.start();
    check(store.items.isEmpty, 'The temporary desktop should start empty');
    final initial = store.refresh();
    await File('${desktop.path}/latest.txt').writeAsString('latest');
    await Future.wait([initial, ...List.generate(100, (_) => store.refresh())]);
    check(
      store.items.length == 1 && store.items.single.key == 'latest.txt',
      'Coalesced DesktopStore scans must retain the real directory final state',
    );
    // Refresh and disposal both cancel directory subscriptions asynchronously.
    // They must not mutate the same list while the other is awaiting cancel.
    final interrupted = List.generate(20, (_) => store.refresh());
    await Future.wait([store.dispose(), ...interrupted]);
    await File('${desktop.path}/after-dispose.txt').writeAsString('ignored');
    await store.refresh();
    check(store.items.length == 1, 'A disposed store must not scan again');
  } finally {
    await store.dispose();
    await temporary.delete(recursive: true);
  }
}

Future<void> main() async {
  await burstAndWaiters();
  await errorsDoNotPoisonQueue();
  await disposalSkipsPendingScans();
  await realDirectoryFinalState();
  stdout.writeln('Desktop refresh coalescing checks passed.');
}
