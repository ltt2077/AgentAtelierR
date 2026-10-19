import 'dart:io';

import 'package:flutter/material.dart';

import 'virtual_phone_wallpapers.dart';

/// Tavern edition: full-screen chat background for the text-first main
/// screen. Shows the selected built-in or imported image (cover-fit) under a
/// soft dark scrim so the glass conversation panel stays readable.
class TavernChatBackground extends StatelessWidget {
  const TavernChatBackground({super.key, required this.store});

  final VirtualPhoneWallpaperStore store;

  static const fallbackColor = Color(0xFF15191B);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final selected = store.selected;
      final ImageProvider image = selected.filePath != null
          ? FileImage(File(selected.filePath!))
          : AssetImage(selected.assetPath!);
      return Stack(
        key: const ValueKey('tavern-chat-background'),
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: fallbackColor),
          Image(
            key: ValueKey(selected.id),
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x66000000)],
              ),
            ),
          ),
        ],
      );
    },
  );
}
