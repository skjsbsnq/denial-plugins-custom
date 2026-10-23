import 'dart:async';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_taskbar_custom/src/anchored_menu_expansion.dart';
import 'package:denial_taskbar_custom/src/control_center.dart';
import 'package:denial_taskbar_custom/src/control_center_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _Audio implements AudioService {
  final updates = StreamController<AudioLevelState>.broadcast(sync: true);
  final reads = <Completer<double?>>[];

  @override
  Stream<AudioLevelState> get states => updates.stream;

  @override
  Future<double?> readLevel() {
    final read = Completer<double?>();
    reads.add(read);
    return read.future;
  }

  void native(double level, {bool muted = false}) => updates.add(
    AudioLevelState(level: level, muted: muted, requestSerial: 0),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioDevices extends AudioDevicesController {
  @override
  AudioDevicesState build() => const AudioDevicesState(
    devices: [],
    loading: false,
    changing: false,
    error: null,
  );
}

class _Network extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() => NetworkConnectivityState.initial();
}

class _Bluetooth extends BluetoothController {
  @override
  BluetoothState build() => BluetoothState.initial();
}

class _Displays extends DisplayLayoutController {
  @override
  DisplayLayout? build() => null;
}

class _Brightness extends DisplayBrightnessController {
  @override
  DisplayBrightnessState build() =>
      const DisplayBrightnessState(levels: {}, loading: {});
}

class _Notifications extends DesktopNotificationsController {
  @override
  DesktopNotificationsState build() => const DesktopNotificationsState();
}

class _Services implements ShellServices {
  final _bounds = Provider<Rect?>((ref) => const Rect.fromLTWH(0, 0, 800, 600));
  final previews = <double>[];
  final commits = <double>[];
  var beginnings = 0;

  @override
  Provider<Rect?> monitorBounds(int monitorId) => _bounds;

  @override
  final connectedWifi = Provider<WifiNetwork?>((ref) => null);

  @override
  void beginVolumeInteraction() => beginnings++;

  @override
  void setVolume(double value) => previews.add(value);

  @override
  void commitVolume(double value) => commits.add(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_Audio audio, _Services services) => ProviderScope(
  overrides: [
    shellSettingsProvider.overrideWith(_Settings.new),
    audioServiceProvider.overrideWithValue(audio),
    audioDevicesProvider.overrideWith(_AudioDevices.new),
    networkConnectivityProvider.overrideWith(_Network.new),
    bluetoothProvider.overrideWith(_Bluetooth.new),
    displayLayoutProvider.overrideWith(_Displays.new),
    displayBrightnessProvider.overrideWith(_Brightness.new),
    desktopNotificationsProvider.overrideWith(_Notifications.new),
  ],
  child: ShellServicesScope(
    services: services,
    child: ShellTheme(
      data: const ShellThemeData(panelOpacity: 1),
      child: const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: ControlCenterButton(monitorId: 0),
          ),
        ),
      ),
    ),
  ),
);

Slider _volume(WidgetTester tester) =>
    tester.widgetList<Slider>(find.byType(Slider)).first;

Future<void> _open(
  WidgetTester tester,
  _Audio audio,
  _Services services,
) async {
  await tester.pumpWidget(_host(audio, services));
  await tester.tap(find.byTooltip('Control center'));
  await tester.pumpAndSettle();
  expect(audio.reads, hasLength(1));
}

void main() {
  testWidgets('volume events and drags retain other controls and menu state', (
    tester,
  ) async {
    final audio = _Audio();
    final services = _Services();
    await _open(tester, audio, services);
    expect(_volume(tester).onChanged, isNull);
    expect(find.text('Reading volume…'), findsOneWidget);

    audio.native(.45);
    await tester.pump();
    expect(_volume(tester).value, .45);
    audio.reads.single.complete(.1);
    await tester.pump();
    expect(_volume(tester).value, .45);

    await tester.tap(find.text('Output device'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh devices').hitTestable(), findsOneWidget);
    final header = tester.widget<ControlCenterHeader>(
      find.byType(ControlCenterHeader),
    );
    final menu = tester.widget<AnchoredMenuExpansion>(
      find.byType(AnchoredMenuExpansion),
    );
    final output = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    final brightness = tester.widgetList<Slider>(find.byType(Slider)).last;

    _volume(tester).onChangeStart!(.45);
    _volume(tester).onChanged!(.8);
    await tester.pump();
    expect(_volume(tester).value, .8);
    final dragging = _volume(tester);
    audio.native(.2);
    await tester.pump();
    expect(_volume(tester), same(dragging));
    _volume(tester).onChangeEnd!(.8);
    audio.native(.8);
    await tester.pump();
    expect(services.beginnings, 1);
    expect(services.previews, [.8]);
    expect(services.commits, [.8]);
    audio.native(.6);
    await tester.pump();
    expect(_volume(tester).value, .6);
    audio.native(.6, muted: true);
    await tester.pump();
    expect(_volume(tester).value, 0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(
      tester.widget<ControlCenterHeader>(find.byType(ControlCenterHeader)),
      same(header),
    );
    expect(
      tester.widget<AnchoredMenuExpansion>(find.byType(AnchoredMenuExpansion)),
      same(menu),
    );
    expect(
      tester.widget<ExpansionTile>(find.byType(ExpansionTile)),
      same(output),
    );
    expect(
      tester.widgetList<Slider>(find.byType(Slider)).last,
      same(brightness),
    );
    expect(find.text('Refresh devices').hitTestable(), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    audio.native(.3);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    await audio.updates.close();
  });

  testWidgets('read failure, retry and delayed reads remain local and safe', (
    tester,
  ) async {
    final audio = _Audio();
    final services = _Services();
    await _open(tester, audio, services);
    audio.reads.single.completeError(StateError('read failed'));
    await tester.pump();
    expect(find.text('Unable to read volume'), findsOneWidget);
    expect(_volume(tester).onChanged, isNull);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    expect(audio.reads, hasLength(2));
    audio.reads.last.complete(.3);
    await tester.pump();
    expect(_volume(tester).value, .3);
    expect(find.text('Unable to read volume'), findsNothing);

    _volume(tester).onChangeEnd!(.9);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(audio.reads, hasLength(3));
    audio.reads.last.complete(.4);
    await tester.pump();
    expect(_volume(tester).value, .4);

    _volume(tester).onChangeEnd!(.7);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(audio.reads, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
    audio.reads.last.complete(.2);
    audio.native(.2);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    await audio.updates.close();
  });
}
