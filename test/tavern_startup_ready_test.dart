// Tavern edition regression test for "stuck on 加载中" (1.0.4.2).
//
// The bootstrap overlay in main.dart only disappears after ChatScreen calls
// onCharacterReady / onCharacterLoadFailed. Those used to be fired only by the
// Spine view or static portrait; the text-first stage builds neither, so the
// startup loader must still be released.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ryza_chat_mvp/src/app_controller.dart';
import 'package:ryza_chat_mvp/src/chat_screen.dart';
import 'package:ryza_chat_mvp/src/settings_slots.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<int> mountAndCountReady(
    WidgetTester tester,
    AppController controller,
  ) async {
    var ready = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          controller: controller,
          onMenuPressed: () {},
          onShopPressed: () {},
          hideUi: false,
          onCharacterReady: () => ready++,
          onCharacterLoadFailed: () => ready++,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return ready;
  }

  testWidgets('first install (default Ryza) releases the startup loader', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    final ready = await mountAndCountReady(tester, controller);
    expect(ready, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('first install with Sophie releases the startup loader', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'active_character_id_v1': 'sophie',
    });
    final controller = await AppController.load();
    final ready = await mountAndCountReady(tester, controller);
    expect(ready, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'upgrade from 1.0.4.1 state (tavern slot active) releases the loader',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Simulate a 1.0.4.1 install: tavern card 8 chosen, then app restarted.
      final old = await AppController.load();
      final bank = old.settingsSlots(SettingsSlotKind.character)..active = 7;
      old.saveSettingsSlots(SettingsSlotKind.character, bank);
      await tester.pump(const Duration(milliseconds: 600));
      old.dispose();

      final controller = await AppController.load();
      expect(controller.settingsSlots(SettingsSlotKind.character).active, 7);
      expect(controller.tavernModeActive, isTrue);
      expect(controller.chatBackgrounds.selected.id, 'tavern-default');
      final ready = await mountAndCountReady(tester, controller);
      expect(ready, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('a broken custom background never blocks startup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'tavern.chat_backgrounds.v1': '{"selected":"imported-0123456789abcdef0123456789abcdef","imports":[{"id":"imported-0123456789abcdef0123456789abcdef","name":"x","path":"/nonexistent/x.png"}]}',
      'tavern.chat_backgrounds.v1.garbage': 'x',
    });
    final controller = await AppController.load();
    final ready = await mountAndCountReady(tester, controller);
    expect(ready, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
