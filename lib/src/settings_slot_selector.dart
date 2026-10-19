import 'package:flutter/material.dart';

import 'app_localization.dart';
import 'settings_slots.dart';

class SettingsSlotSelector extends StatelessWidget {
  const SettingsSlotSelector({
    super.key,
    required this.slots,
    required this.language,
    required this.onSelected,
    this.names = const [],
  });

  final SettingsSlots slots;
  final AppLanguage language;
  final ValueChanged<int> onSelected;

  /// Optional per-slot names (tavern presets); null keeps the number only.
  final List<String?> names;

  String? _name(int i) => i < names.length ? names[i] : null;

  @override
  Widget build(BuildContext context) {
    final activeName = _name(slots.active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          language.text('槽位', 'Slots', '枠'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        // Tavern edition: 20 slots, so chips show only the number and stay
        // compact; the selected slot's preset name is shown below.
        Wrap(
          spacing: 4,
          runSpacing: 2,
          children: [
            for (var i = 0; i < SettingsSlots.count; i++)
              Tooltip(
                message: _name(i) == null
                    ? language.text('槽位 ${i + 1}', 'Slot ${i + 1}', '${i + 1}枠')
                    : '${i + 1} · ${_name(i)}',
                child: ChoiceChip(
                  key: ValueKey('settings-slot-$i'),
                  selected: slots.active == i,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  showCheckmark: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  label: Text('${i + 1}'),
                  avatar: slots.entries[i] == null
                      ? const Icon(Icons.add_rounded, size: 14)
                      : null,
                  onSelected: (_) => onSelected(i),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          language.text(
            '当前：槽位 ${slots.active + 1}${activeName == null ? '' : ' · $activeName'}',
            'Current: slot ${slots.active + 1}${activeName == null ? '' : ' · $activeName'}',
            '現在：${slots.active + 1}枠${activeName == null ? '' : ' · $activeName'}',
          ),
          key: const ValueKey('settings-slot-current'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          language.text(
            '切换时保留本次编辑；保存后使用所选槽位。取消不保存。',
            'Switching keeps drafts. Save to use the selected slot; Cancel discards edits.',
            '切替時は下書きを保持。保存で選択枠を使用し、キャンセルで編集を破棄します。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
