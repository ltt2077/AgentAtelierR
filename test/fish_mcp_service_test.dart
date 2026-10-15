import 'package:flutter_test/flutter_test.dart';

import 'package:ryza_chat_mvp/src/app_controller.dart';
import 'package:ryza_chat_mvp/src/fish_mcp_service.dart';

void main() {
  test('Fish MCP is an OAuth provider and does not require an API key', () {
    expect(TtsProvider.fishAudioMcp.requiresApiKey, isFalse);
    expect(TtsProvider.fishAudioMcp.label, contains('MCP'));
  });

  test('Fish MCP blocks paid generation before tools/list discovery', () async {
    final service = FishMcpService.instance;
    await service.disconnect(clearError: true);
    await expectLater(
      service.synthesize(text: 'こんにちは'),
      throwsA(
        isA<FishMcpException>()
            .having((error) => error.stage, 'stage', 'preflight')
            .having((error) => error.code, 'code', 'not_ready')
            .having((error) => error.generationSubmitted, 'submitted', false),
      ),
    );
  });
}
