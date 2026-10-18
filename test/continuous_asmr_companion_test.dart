import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ryza_chat_mvp/src/android_companion_runtime.dart';
import 'package:ryza_chat_mvp/src/app_controller.dart';
import 'package:ryza_chat_mvp/src/continuous_asmr_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ASMR stops only for companion stop and rejects new preparation', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final channels = <String>{
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'agent_atelier_r/companion_runtime',
      'agent_atelier_r/companion_runtime/events',
      'plugins.flutter.io/path_provider',
    };
    final state = <String, Object>{
      'running': true,
      'stopRequested': false,
      'muted': false,
      'callActive': false,
      'notificationsAllowed': true,
    };
    messenger.setMockMethodCallHandler(
      const MethodChannel('agent_atelier_r/companion_runtime'),
      (_) async => Map<String, Object>.from(state),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('agent_atelier_r/companion_runtime/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          final events = 'xyz.luan/audioplayers/events/$id';
          channels.add(events);
          messenger.setMockMethodCallHandler(
            MethodChannel(events),
            (_) async => null,
          );
        }
        return 0;
      },
    );
    addTearDown(() {
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      }
    });
    SharedPreferences.setMockInitialValues({});
    final controller = (await tester.runAsync(() => AppController.load()))!;
    addTearDown(controller.dispose);
    final runtime = AndroidCompanionRuntime.instance;
    await runtime.refresh();
    await tester.pumpWidget(
      MaterialApp(home: ContinuousAsmrPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    state.addAll({'muted': true, 'callActive': true});
    await runtime.refresh();
    await tester.pumpAndSettle();
    expect(find.text('后台陪伴已停止'), findsNothing);

    state['stopRequested'] = true;
    await runtime.refresh();
    await tester.pumpAndSettle();
    expect(find.text('后台陪伴已停止'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '雨声');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    const instruction = '后台陪伴已停止，请在“设置 → 声音”中恢复陪伴通知后重试';
    expect(find.text(instruction), findsOneWidget);
    expect(find.text('请先启用并配置 LLM 和语音合成'), findsNothing);

    // Further native updates while already stopped do not stop the session again.
    state.addAll({'muted': false, 'callActive': false});
    await runtime.refresh();
    await tester.pumpAndSettle();
    expect(find.text(instruction), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    state['stopRequested'] = false;
    await runtime.refresh();
    expect(tester.takeException(), isNull);
  });
}
