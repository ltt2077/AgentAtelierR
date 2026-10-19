// Tavern edition: backup compatibility between the original 5-slot app and
// the 20-slot tavern build. The fixtures in test/fixtures were exported by the
// unmodified original source (commit 933a54d) via AppController.exportData()
// and AppController.exportLocalSlot().
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ryza_chat_mvp/src/app_controller.dart';
import 'package:ryza_chat_mvp/src/character_prompt_defaults.dart';
import 'package:ryza_chat_mvp/src/settings_slots.dart';
import 'package:ryza_chat_mvp/src/tavern_presets.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('there are 20 slots and 19 adult tavern presets', () {
    expect(SettingsSlots.count, 20);
    expect(tavernPresets.length, SettingsSlots.count - 1);
    expect(tavernPresetForSlot(0), isNull);
    expect(tavernPresetForSlot(20), isNull);
    expect(tavernPresetHeader, contains('18 岁以上'));
    expect(tavernPresetHeader, contains('禁止任何涉及未成年'));
    for (final preset in tavernPresets) {
      expect(preset.persona, startsWith(tavernPresetHeader));
      expect(preset.persona, isNot(contains('非露骨')));
      expect(preset.persona, isNot(contains('不描写性行为')));
      expect(preset.worldBody.trim(), isNotEmpty);
    }
    expect(tavernPresets.map((p) => p.name).toSet().length, 19);
  });

  test('fresh install: slot 1 is the original default, 2-20 are presets', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await AppController.load();
    addTearDown(c.dispose);
    final character = c.settingsSlots(SettingsSlotKind.character);
    final world = c.settingsSlots(SettingsSlotKind.world);
    expect(character.active, 0);
    expect(c.editableCharacterPersona, defaultCharacterPersona);
    for (var i = 1; i < SettingsSlots.count; i++) {
      expect(character.entries[i]?['text'], tavernPresets[i - 1].persona);
      expect(world.entries[i]?['text'], tavernPresets[i - 1].worldBody);
    }
    expect(
      c.settingsSlots(SettingsSlotKind.user).entries.skip(1),
      everyElement(isNull),
    );
    // Original slot 1 prompt keeps the original wording and rules.
    expect(c.tavernModeActive, isFalse);
    expect(c.buildCharacterPrompt(), contains('你扮演莱莎'));

    // Choosing tavern slot 7 also moves the world book off the original slot.
    c.saveSettingsSlots(SettingsSlotKind.character, character..active = 6);
    expect(c.characterPersona, tavernPresets[5].persona);
    expect(c.settingsSlots(SettingsSlotKind.world).active, 6);
    expect(c.worldSetting, tavernPresets[5].worldBody);
    expect(c.tavernModeActive, isTrue);
    final prompt = c.buildCharacterPrompt();
    expect(prompt, contains('成年向酒馆角色扮演'));
    expect(prompt, isNot(contains('非露骨')));
    expect(prompt, isNot(contains('你扮演莱莎，')));
    expect(prompt, contains('瓦瑟琳'));
  });

  test('original v1 backup imports into slots 1-5, 6-20 stay default', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await AppController.load();
    addTearDown(c.dispose);
    final backup = _fixture('original_v1_backup.json');
    expect(backup['format'], 'agent-atelier-r-local-backup');
    expect(backup['version'], 1);
    expect((backup['settingsSlots'] as Map)['character'], isNot(contains('version')));
    await c.importData(backup);

    final character = c.settingsSlots(SettingsSlotKind.character);
    final world = c.settingsSlots(SettingsSlotKind.world);
    final user = c.settingsSlots(SettingsSlotKind.user);
    expect(character.active, 4);
    expect(c.characterPersona, '旧版槽位5人物');
    expect(character.entries[0]?['text'], '旧版槽位1人物');
    expect(character.entries[1]?['text'], '旧版槽位2人物');
    expect(character.entries[4]?['text'], '旧版槽位5人物');
    // Unused old slots and the new slots 6-20 fall back to tavern presets.
    expect(character.entries[2]?['text'], tavernPresets[1].persona);
    for (var i = SettingsSlots.legacyCount; i < SettingsSlots.count; i++) {
      expect(character.entries[i]?['text'], tavernPresets[i - 1].persona);
      expect(world.entries[i]?['text'], tavernPresets[i - 1].worldBody);
      expect(user.entries[i], isNull);
    }
    expect(world.active, 3);
    expect(c.worldSetting, '旧版槽位4世界');
    expect(world.entries[0]?['text'], '旧版槽位1世界');
    expect(user.entries[2]?['address'], '旧版槽位3称呼');
    expect(c.userAddress, '旧版称呼');
    // Custom old slot 5 has no tavern header: keep the original identity.
    expect(c.tavernModeActive, isFalse);
    expect(c.buildCharacterPrompt(), contains('旧版槽位5人物'));
  });

  test('original v1 game save imports and keeps its active slot indices', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await AppController.load();
    addTearDown(c.dispose);
    final save = _fixture('original_v1_game_save.json');
    expect(save['format'], 'agent-atelier-r-save-slot');
    await c.importLocalSlot(1, save);
    await c.loadFromLocalSlot(1);
    expect(c.settingsSlots(SettingsSlotKind.character).active, 4);
    expect(c.characterPersona, '旧版槽位5人物');
    expect(c.settingsSlots(SettingsSlotKind.world).active, 3);
    expect(c.worldSetting, '旧版槽位4世界');
  });

  test('new v2 backup round-trips all 20 slots', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await AppController.load();
    addTearDown(c.dispose);
    final character = c.settingsSlots(SettingsSlotKind.character);
    character.entries[19] = {'text': '${tavernPresetMarker}自定义第20槽'};
    character.entries[11] = {'text': '自定义第12槽'};
    c.saveSettingsSlots(SettingsSlotKind.character, character..active = 19);
    final backup =
        jsonDecode(jsonEncode(c.exportData())) as Map<String, dynamic>;
    expect(backup['version'], 1, reason: 'top-level format stays readable');
    final banks = backup['settingsSlots'] as Map<String, dynamic>;
    for (final kind in SettingsSlotKind.values) {
      final bank = banks[kind.name] as Map<String, dynamic>;
      expect(bank['version'], SettingsSlots.schemaVersion);
      expect((bank['entries'] as List).length, SettingsSlots.count);
    }
    File('build/tavern_v2_backup.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(backup));

    SharedPreferences.setMockInitialValues({});
    final restored = await AppController.load();
    addTearDown(restored.dispose);
    await restored.importData(backup);
    final slots = restored.settingsSlots(SettingsSlotKind.character);
    expect(slots.active, 19);
    expect(restored.characterPersona, '${tavernPresetMarker}自定义第20槽');
    expect(slots.entries[11]?['text'], '自定义第12槽');
    expect(restored.tavernModeActive, isTrue);
    expect(restored.settingsSlots(SettingsSlotKind.world).active, 19);
  });

  test('a v1 bank never reads past five slots; v2 reads twenty', () {
    final entries = List.generate(20, (i) => {'text': '槽$i'});
    final v1 = SettingsSlots.fromJson({'active': 12, 'entries': entries});
    expect(v1.active, SettingsSlots.legacyCount - 1);
    expect(v1.entries.where((e) => e != null).length, SettingsSlots.legacyCount);
    final v2 = SettingsSlots.fromJson({
      'version': 2,
      'active': 12,
      'entries': entries,
    });
    expect(v2.active, 12);
    expect(v2.entries[19]?['text'], '槽19');
    expect(SettingsSlots.versionOf({'version': 'x'}), 1);
    expect(SettingsSlots.versionOf(null), 1);
  });
}
