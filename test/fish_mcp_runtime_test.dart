import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:ryza_chat_mvp/src/fish_mcp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// These tests exercise the complete local service path. The ID3 bytes only
// identify an MP3 container; playback and provider generation are not invoked.
const _mp3 = <int>[0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0];

Tool _tool({
  String name = 'text_to_speech',
  String? description,
  Map<String, dynamic> properties = const {},
}) => Tool(
  name: name,
  description: description,
  inputSchema: JsonSchema.fromJson({
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'minLength': 1},
      ...properties,
    },
    'required': ['text'],
    'additionalProperties': false,
  }),
);

CallToolResult _inlineResult() => CallToolResult(
  content: [AudioContent(data: base64Encode(_mp3), mimeType: 'audio/mpeg')],
);

class _FakeMcpClient extends McpClient {
  _FakeMcpClient({
    Map<String?, ListToolsResult>? pages,
    FutureOr<CallToolResult> Function(CallToolRequest request)? onCall,
  }) : pages =
           pages ??
           {
             null: ListToolsResult(tools: [_tool()]),
           },
       onCall = onCall ?? ((_) => _inlineResult()),
       super(const Implementation(name: 'local-test-only', version: '1'));

  final Map<String?, ListToolsResult> pages;
  final FutureOr<CallToolResult> Function(CallToolRequest request) onCall;
  final List<String?> cursors = [];
  final List<CallToolRequest> requests = [];

  @override
  Future<ListToolsResult> listTools({
    ListToolsRequest? params,
    RequestOptions? options,
  }) async {
    cursors.add(params?.cursor);
    return pages[params?.cursor]!;
  }

  @override
  Future<CallToolResult> callTool(
    CallToolRequest params, {
    RequestOptions? options,
  }) async {
    requests.add(params);
    return onCall(params);
  }

  @override
  Future<void> close() async {}
}

// Force a connection change exactly when an output path is first used. This
// models a disconnect during file creation without sleeps or large files.
class _DirectoryOnPath extends Fake implements Directory {
  _DirectoryOnPath(this.directory, this.onPath);

  final Directory directory;
  final void Function() onPath;
  bool _fired = false;

  @override
  String get path {
    if (!_fired) {
      _fired = true;
      onPath();
    }
    return directory.path;
  }
}

class _Harness {
  _Harness(this.service, this.client, this.downloads, this.directory);

  final FishMcpService service;
  final _FakeMcpClient client;
  final List<http.Request> downloads;
  final Directory directory;

  static Future<_Harness> create({
    _FakeMcpClient? client,
    FutureOr<http.Response> Function(http.Request request)? onDownload,
    Future<Directory> Function(Directory directory)? onTemporaryDirectory,
  }) async {
    final directory = await Directory.systemTemp.createTemp('fish-mcp-local-');
    final fake = client ?? _FakeMcpClient();
    final downloads = <http.Request>[];
    final downloadClient = MockClient((request) async {
      downloads.add(request);
      if (onDownload == null) {
        fail('No audio download was expected: ${request.url.host}');
      }
      return await onDownload(request);
    });
    final service = FishMcpService.forTesting(
      client: fake,
      downloadClient: downloadClient,
      temporaryDirectory: () =>
          onTemporaryDirectory?.call(directory) ?? Future.value(directory),
    );
    addTearDown(() async {
      await service.disconnect();
      service.dispose();
      downloadClient.close();
      await directory.delete(recursive: true);
    });
    return _Harness(service, fake, downloads, directory);
  }
}

Future<FishMcpException> _failure(Future<String> result) async {
  try {
    await result;
  } on FishMcpException catch (error) {
    return error;
  }
  fail('Expected FishMcpException');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'paged discovery selects generation rather than free balance tools',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          pages: {
            null: ListToolsResult(
              tools: [
                _tool(
                  name: 'get_credit_balance',
                  description: 'Read credits for text-to-speech generation',
                ),
                _tool(name: 'tts'),
              ],
              nextCursor: 'page-2',
            ),
            'page-2': ListToolsResult(tools: [_tool()]),
          },
        ),
      );
      await harness.service.discoverTools();
      expect(harness.client.cursors, [null, 'page-2']);
      expect(harness.service.ttsToolName, 'text_to_speech');
      expect(harness.service.tools, hasLength(3));
      final path = await harness.service.synthesize(text: 'ローカルテスト');
      expect(harness.client.requests.single.name, 'text_to_speech');
      expect(await File(path).readAsBytes(), _mp3);
      expect(harness.downloads, isEmpty);
    },
  );

  test(
    'repeating pagination cursor stops discovery without generating',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          pages: {
            null: ListToolsResult(tools: [_tool()], nextCursor: 'same'),
            'same': ListToolsResult(tools: [_tool()], nextCursor: 'same'),
          },
        ),
      );
      await expectLater(
        harness.service.discoverTools(),
        throwsA(
          isA<FishMcpException>().having(
            (e) => e.code,
            'code',
            'invalid_cursor',
          ),
        ),
      );
      expect(harness.client.cursors, [null, 'same']);
      expect(harness.client.requests, isEmpty);
      expect(harness.service.isReady, isFalse);
    },
  );

  test('tool error retains evidence and never resubmits generation', () async {
    final harness = await _Harness.create(
      client: _FakeMcpClient(
        onCall: (_) => const CallToolResult(
          content: [TextContent(text: 'Generic outer tool error')],
          isError: true,
          structuredContent: {
            'error': {
              'code': 'synthetic_plan_denied',
              'message': 'Synthetic account restriction',
            },
            'status': 402,
            'request_id': 'req-local-integration-001',
          },
        ),
      ),
    );
    await harness.service.discoverTools();
    final error = await _failure(harness.service.synthesize(text: '非公開の台詞'));
    expect(error.stage, 'result');
    expect(error.code, 'synthetic_plan_denied');
    expect(error.message, 'Synthetic account restriction');
    expect(error.status, 402);
    expect(error.requestId, 'req-local-integration-001');
    expect(error.generationSubmitted, isTrue);
    expect(error.allowsRestFallback, isFalse);
    expect(harness.service.lastError, same(error));
    expect(harness.client.requests, hasLength(1));
    expect(harness.downloads, isEmpty);
  });

  for (final resultKind in ['inline', 'url']) {
    test(
      'disconnect discards delayed $resultKind generation without writing or downloading',
      () async {
        final submitted = Completer<void>();
        final completed = Completer<CallToolResult>();
        final harness = await _Harness.create(
          client: _FakeMcpClient(
            onCall: (_) {
              submitted.complete();
              return completed.future;
            },
          ),
        );
        await harness.service.discoverTools();
        final failure = _failure(harness.service.synthesize(text: '非公開の遅延テスト'));
        await submitted.future;
        await harness.service.disconnect();
        completed.complete(
          resultKind == 'inline'
              ? _inlineResult()
              : const CallToolResult(
                  content: [
                    TextContent(text: 'https://fish.audio/late-result.mp3'),
                  ],
                ),
        );
        final error = await failure;
        expect(error.code, 'connection_changed');
        expect(error.generationSubmitted, isTrue);
        expect(error.allowsRestFallback, isFalse);
        expect(harness.service.state, FishMcpConnectionState.disconnected);
        expect(harness.service.isReady, isFalse);
        expect(harness.client.requests, hasLength(1));
        expect(harness.downloads, isEmpty);
        expect(await harness.directory.list().toList(), isEmpty);
      },
    );
  }

  test(
    'disconnect while resolving output directory never creates audio',
    () async {
      final requested = Completer<Directory>();
      final released = Completer<Directory>();
      final harness = await _Harness.create(
        onTemporaryDirectory: (directory) {
          requested.complete(directory);
          return released.future;
        },
      );
      await harness.service.discoverTools();
      final failure = _failure(harness.service.synthesize(text: 'local'));
      final directory = await requested.future;
      await harness.service.disconnect();
      released.complete(directory);
      final error = await failure;
      expect(error.code, 'connection_changed');
      expect(error.allowsRestFallback, isFalse);
      expect(harness.client.requests, hasLength(1));
      expect(await harness.directory.list().toList(), isEmpty);
    },
  );

  test(
    'disconnect during output creation removes the discarded file',
    () async {
      late FishMcpService service;
      final harness = await _Harness.create(
        onTemporaryDirectory: (directory) async =>
            _DirectoryOnPath(directory, () => unawaited(service.disconnect())),
      );
      service = harness.service;
      await service.discoverTools();
      final error = await _failure(service.synthesize(text: 'local'));
      expect(error.code, 'connection_changed');
      expect(error.allowsRestFallback, isFalse);
      expect(harness.client.requests, hasLength(1));
      expect(await harness.directory.list().toList(), isEmpty);
    },
  );

  test(
    'failed rediscovery invalidates the previously usable generation tool',
    () async {
      final harness = await _Harness.create();
      await harness.service.discoverTools();
      expect(harness.service.isReady, isTrue);
      harness.client.pages[null] = ListToolsResult(
        tools: [_tool()],
        nextCursor: 'repeat',
      );
      harness.client.pages['repeat'] = ListToolsResult(
        tools: [_tool()],
        nextCursor: 'repeat',
      );
      await expectLater(
        harness.service.discoverTools(),
        throwsA(
          isA<FishMcpException>().having(
            (e) => e.code,
            'code',
            'invalid_cursor',
          ),
        ),
      );
      expect(harness.service.isReady, isFalse);
      expect(harness.service.state, FishMcpConnectionState.error);
      final error = await _failure(harness.service.synthesize(text: 'local'));
      expect(error.code, 'not_ready');
      expect(error.generationSubmitted, isFalse);
      expect(harness.client.requests, isEmpty);
      expect(harness.downloads, isEmpty);
    },
  );

  test(
    'configured model reaches generation when absent from discovery schema',
    () async {
      final harness = await _Harness.create();
      await harness.service.discoverTools();
      final path = await harness.service.synthesize(
        text: '非公開の台詞',
        model: 'drama-3',
        voice: 'configured-voice',
      );
      expect(path, endsWith('.mp3'));
      expect(harness.client.requests.single.arguments, {
        'text': '非公開の台詞',
        'model': 'drama-3',
        'voice_id': 'configured-voice',
      });
      expect(harness.service.lastError, isNull);
      expect(harness.downloads, isEmpty);
    },
  );

  for (final alias in ['model', 'model_id', 'modelId']) {
    test(
      'configured model bypasses stale $alias enum and reaches cloud',
      () async {
        final harness = await _Harness.create(
          client: _FakeMcpClient(
            pages: {
              null: ListToolsResult(
                tools: [
                  _tool(
                    properties: {
                      alias: {
                        'type': 'string',
                        'enum': ['old-server-model'],
                      },
                    },
                  ),
                ],
              ),
            },
          ),
        );
        await harness.service.discoverTools();
        expect(
          await harness.service.synthesize(text: 'local', model: 'drama-3'),
          endsWith('.mp3'),
        );
        expect(harness.client.requests.single.arguments, {
          'text': 'local',
          alias: 'drama-3',
        });
        expect(harness.downloads, isEmpty);
      },
    );
  }

  test(
    'incomplete text schema uses canonical text and preserves cloud rejection',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          pages: {
            null: ListToolsResult(
              tools: [
                Tool(
                  name: 'text_to_speech',
                  inputSchema: JsonSchema.fromJson({
                    'type': 'object',
                    'properties': {
                      'content_new': {'type': 'string'},
                    },
                    'required': ['content_new', 'new_remote_field'],
                    'additionalProperties': false,
                  }),
                ),
              ],
            ),
          },
          onCall: (_) => const CallToolResult(
            content: [],
            isError: true,
            structuredContent: {
              'error': {
                'code': 'cloud_invalid_input',
                'message': 'Cloud rejected the request',
              },
              'request_id': 'req-cloud-validation',
            },
          ),
        ),
      );
      await harness.service.discoverTools();
      expect(harness.service.isReady, isTrue);
      final error = await _failure(
        harness.service.synthesize(text: 'local', model: 'drama-3'),
      );
      expect(harness.client.requests.single.arguments, {
        'text': 'local',
        'model': 'drama-3',
      });
      expect(error.code, 'cloud_invalid_input');
      expect(error.message, 'Cloud rejected the request');
      expect(error.requestId, 'req-cloud-validation');
      expect(error.generationSubmitted, isTrue);
      expect(error.allowsRestFallback, isFalse);
    },
  );

  test(
    'language maps to real enum and MP3 result keeps its actual suffix',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          pages: {
            null: ListToolsResult(
              tools: [
                _tool(
                  properties: {
                    'language': {
                      'type': 'string',
                      'enum': ['Japanese', 'English'],
                    },
                    'output_format': {
                      'type': 'string',
                      'enum': ['wav', 'mp3'],
                    },
                    'voice_id': {'type': 'string'},
                  },
                ),
              ],
            ),
          },
          onCall: (_) => const CallToolResult(
            content: [
              TextContent(
                text: '[音频下载](https://cdn.fish.audio/result.mp3?signature=local-secret)',
              ),
            ],
          ),
        ),
        onDownload: (request) {
          expect(
            request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(
            _mp3,
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        },
      );
      await harness.service.discoverTools();
      final path = await harness.service.synthesize(
        text: '秘密のテスト台詞',
        language: 'ja',
        format: 'wav',
        voice: 'local-voice',
      );
      expect(harness.client.requests.single.arguments, {
        'text': '秘密のテスト台詞',
        'language': 'Japanese',
        'output_format': 'wav',
        'voice_id': 'local-voice',
      });
      expect(path, endsWith('.mp3'));
      expect(await File(path).readAsBytes(), _mp3);
      expect(harness.downloads, hasLength(1));
      expect(harness.service.diagnosticReport, isNot(contains('秘密のテスト台詞')));
      expect(harness.service.diagnosticReport, isNot(contains('local-secret')));
    },
  );

  test('resource link downloads audio without regenerating', () async {
    final harness = await _Harness.create(
      client: _FakeMcpClient(
        onCall: (_) => const CallToolResult(
          content: [
            ResourceLink(
              uri: 'https://fish.audio/result.mp3',
              name: 'speech',
              mimeType: 'audio/mpeg',
            ),
          ],
        ),
      ),
      onDownload: (_) => http.Response.bytes(
        _mp3,
        200,
        headers: {'content-type': 'application/octet-stream'},
      ),
    );
    await harness.service.discoverTools();
    expect(await harness.service.synthesize(text: 'local'), endsWith('.mp3'));
    expect(harness.client.requests, hasLength(1));
    expect(harness.downloads, hasLength(1));
  });

  test(
    'array structured content retains nested audio instead of losing it',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          onCall: (_) => CallToolResult(
            content: const [],
            structuredContentJson: JsonValue.array([
              {
                'result': {'audio_url': 'https://fish.audio/array-result.mp3'},
              },
            ]),
          ),
        ),
        onDownload: (_) => http.Response.bytes(
          _mp3,
          200,
          headers: {'content-type': 'audio/mpeg'},
        ),
      );
      await harness.service.discoverTools();
      final path = await harness.service.synthesize(text: '非公開の配列テスト');
      expect(path, endsWith('.mp3'));
      expect(await File(path).readAsBytes(), _mp3);
      expect(harness.client.requests, hasLength(1));
      expect(harness.downloads, hasLength(1));
      expect(harness.service.lastError, isNull);
      final report = jsonDecode(harness.service.diagnosticReport) as Map;
      expect(
        (report['last_result'] as Map).containsKey('structured_keys'),
        isFalse,
      );
    },
  );

  for (final entry in {
    'http://fish.audio/result.mp3': 'unsafe_audio_url',
    'https://untrusted.invalid/result.mp3': 'untrusted_audio_host',
    'https://fish.audio:8443/result.mp3': 'unsafe_audio_port',
  }.entries) {
    test(
      'unsafe result URL is rejected before download: ${entry.key}',
      () async {
        final harness = await _Harness.create(
          client: _FakeMcpClient(
            onCall: (_) =>
                CallToolResult(content: [TextContent(text: entry.key)]),
          ),
        );
        await harness.service.discoverTools();
        final error = await _failure(harness.service.synthesize(text: 'local'));
        expect(error.code, entry.value);
        expect(error.generationSubmitted, isTrue);
        expect(error.allowsRestFallback, isFalse);
        expect(harness.client.requests, hasLength(1));
        expect(harness.downloads, isEmpty);
      },
    );
  }

  test(
    'download redirect is revalidated and sends no request to unsafe host',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          onCall: (_) => const CallToolResult(
            content: [TextContent(text: 'https://fish.audio/result.mp3')],
          ),
        ),
        onDownload: (_) => http.Response(
          '',
          302,
          headers: {'location': 'https://untrusted.invalid/stolen.mp3'},
        ),
      );
      await harness.service.discoverTools();
      final error = await _failure(harness.service.synthesize(text: 'local'));
      expect(error.code, 'untrusted_audio_host');
      expect(error.allowsRestFallback, isFalse);
      expect(harness.client.requests, hasLength(1));
      expect(harness.downloads.single.url.host, 'fish.audio');
    },
  );

  test('non-audio response never writes a file or regenerates', () async {
    final harness = await _Harness.create(
      client: _FakeMcpClient(
        onCall: (_) => const CallToolResult(
          content: [TextContent(text: 'https://fish.audio/result.mp3')],
        ),
      ),
      onDownload: (_) => http.Response(
        'not an audio container',
        200,
        headers: {'content-type': 'audio/mpeg'},
      ),
    );
    await harness.service.discoverTools();
    final error = await _failure(harness.service.synthesize(text: 'local'));
    expect(error.code, 'invalid_audio');
    expect(error.stage, 'audio_validate');
    expect(error.allowsRestFallback, isFalse);
    expect(harness.client.requests, hasLength(1));
    expect(harness.downloads, hasLength(1));
  });

  test(
    'audio download HTTP failure keeps request ID and does not retry',
    () async {
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          onCall: (_) => const CallToolResult(
            content: [TextContent(text: 'https://fish.audio/result.mp3')],
          ),
        ),
        onDownload: (_) => http.Response(
          'unavailable',
          503,
          headers: {'x-request-id': 'req-download-002'},
        ),
      );
      await harness.service.discoverTools();
      final error = await _failure(harness.service.synthesize(text: 'local'));
      expect(error.code, 'audio_http_error');
      expect(error.status, 503);
      expect(error.requestId, 'req-download-002');
      expect(error.generationSubmitted, isTrue);
      expect(error.allowsRestFallback, isFalse);
      expect(harness.client.requests, hasLength(1));
      expect(harness.downloads, hasLength(1));
    },
  );

  test(
    'transport failure is outcome unknown and error report redacts secrets',
    () async {
      const privateText = 'PRIVATE_DIALOGUE_NOT_FOR_DIAGNOSTICS';
      final harness = await _Harness.create(
        client: _FakeMcpClient(
          onCall: (_) => throw TimeoutException(
            'Authorization: Bearer local-access-token https://api.fish.audio/mcp?access_token=local-query-token',
          ),
        ),
      );
      await harness.service.discoverTools();
      final error = await _failure(
        harness.service.synthesize(text: privateText),
      );
      expect(error.stage, 'transport');
      expect(error.outcomeUnknown, isTrue);
      expect(error.generationSubmitted, isTrue);
      expect(error.allowsRestFallback, isFalse);
      expect(harness.client.requests, hasLength(1));
      final report = harness.service.diagnosticReport;
      expect(report, isNot(contains(privateText)));
      expect(report, isNot(contains('local-access-token')));
      expect(report, isNot(contains('local-query-token')));
      final decoded = jsonDecode(report) as Map<String, dynamic>;
      expect(
        (decoded['last_request'] as Map)['text_utf8_bytes'],
        utf8.encode(privateText).length,
      );
      expect((decoded['last_error'] as Map)['outcome_unknown'], isTrue);
    },
  );
}
