// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/device_warning.dart';

/// The certified-device warning is asked for once a launch, however often the
/// gate reopens, and a platform that cannot show it is not an error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/device_warning');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  void answer(Future<Object?> Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the first unlock asks the platform to show it', () async {
    answer((_) async => null);
    await DeviceWarning(channel).showIfDue();
    expect(calls, ['showCertifiedDeviceWarning']);
  });

  test('later unlocks in the same launch do not ask again', () async {
    answer((_) async => null);
    final warning = DeviceWarning(channel);
    await warning.showIfDue();
    await warning.showIfDue();
    await warning.showIfDue();
    expect(calls, hasLength(1));
  });

  test('a platform that refuses is swallowed, and not asked again', () async {
    answer((_) async => throw PlatformException(code: 'nope'));
    final warning = DeviceWarning(channel);
    await expectLater(warning.showIfDue(), completes);
    await warning.showIfDue();
    expect(calls, hasLength(1), reason: 'a missing platform stays missing');
  });

  test('no platform side at all is swallowed too', () async {
    calls = [];
    // No handler: the call ends in MissingPluginException, as in widget tests.
    await expectLater(DeviceWarning(channel).showIfDue(), completes);
  });
}
