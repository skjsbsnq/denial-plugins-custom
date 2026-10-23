import 'dart:io';

import 'package:denial_taskbar_custom/src/application_launch_wait.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final slow = ApplicationLaunchWait();
  final request = slow.begin([10])!;
  check(
    slow.begin([10]) == null,
    'Rapid clicks must not submit another launch.',
  );
  check(slow.dispatched(request, started: true), 'Accept the launch reply.');
  check(
    slow.waitingForWindow && slow.busy,
    'A successful dispatch must keep waiting for a real window.',
  );
  check(
    !slow.observeWindows([10]),
    'Existing windows must not finish a launch.',
  );
  check(!slow.observeWindows([]), 'Closing a window is not launch completion.');
  check(
    slow.observeWindows([11]),
    'A new ID must complete even when the window count did not increase.',
  );
  check(!slow.busy, 'A new matching window releases the launch guard.');
  check(
    !slow.expire(request),
    'A late timeout must not alter completed state.',
  );

  final fast = ApplicationLaunchWait();
  final fastRequest = fast.begin([])!;
  check(
    fast.observeWindows([20]),
    'Handle a window arriving before the reply.',
  );
  check(
    !fast.dispatched(fastRequest, started: false) && !fast.busy,
    'A late rejection cannot override an already observed window.',
  );

  final failed = ApplicationLaunchWait();
  final failedRequest = failed.begin([])!;
  check(
    failed.dispatched(failedRequest, started: false) && !failed.busy,
    'Launch rejection must end the wait and allow retry.',
  );
  final retry = failed.begin([])!;
  check(
    !failed.dispatched(failedRequest, started: true),
    'Old replies must not acknowledge a new launch.',
  );
  check(
    !failed.expire(failedRequest) && failed.waitingForWindow,
    'An old deadline must not stop the retry.',
  );
  check(
    failed.expire(retry) && !failed.busy,
    'A missing window must eventually release the launch guard.',
  );
  check(
    !failed.dispatched(retry, started: true) && !failed.busy,
    'A reply after timeout must not restart waiting.',
  );
  check(failed.begin([]) != null, 'Timeout must permit a fresh launch.');

  // Window matching/alias resolution happens before IDs reach this class.
  final independent = ApplicationLaunchWait();
  independent.begin([]);
  check(
    !independent.observeWindows([]) && independent.waitingForWindow,
    'An unrelated application must not finish this launch.',
  );
  check(
    independent.observeWindows([30]),
    'Matching windows on another monitor/workspace must complete normally.',
  );
  stdout.writeln(
    'Application launch acknowledgement, window and retry checks passed.',
  );
}
