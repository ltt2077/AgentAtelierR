import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cryptography/cryptography.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai_services.dart' show detectAudioContainerExtension;
import 'fish_mcp_protocol.dart';
import 'runtime_log.dart';

export 'fish_mcp_protocol.dart' show FishMcpException;

/// Connection state for the Fish Audio MCP transport.
enum FishMcpConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  toolsDiscovered,
  error,
}

class FishMcpToolInfo {
  const FishMcpToolInfo({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'inputSchema': inputSchema,
  };
}

/// OAuth storage and MCP client for Fish Audio.
///
/// OAuth credentials are deliberately kept in a namespace that is not part of
/// ServiceApiBackup. The MCP endpoint is never used until tools/list has
/// completed successfully, so a changed or unavailable server cannot trigger
/// a paid generation call by accident.
class FishMcpService extends ChangeNotifier {
  FishMcpService._()
    : _downloadClient = http.Client(),
      _temporaryDirectory = getTemporaryDirectory,
      _persistDiagnostics = true;

  @visibleForTesting
  FishMcpService.forTesting({
    required this._client,
    required this._downloadClient,
    required this._temporaryDirectory,
  }) : _persistDiagnostics = false {
    state = FishMcpConnectionState.connected;
  }

  static final FishMcpService instance = FishMcpService._();

  static const endpoint = 'https://api.fish.audio/mcp';
  static const callbackUri = 'fishmcp://oauth/callback';
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());
  static const _credentialKey = 'fish_mcp_oauth_v1';
  static const _clientIdKey = 'fish_mcp_client_id_v1';
  static const _registerEndpoint = 'https://api.fish.audio/oauth/register';
  static const _tokenEndpoint = 'https://api.fish.audio/oauth/token';
  static const _authorizeEndpoint = 'https://fish.audio/oauth/authorize/';

  FishMcpConnectionState state = FishMcpConnectionState.disconnected;
  String? errorMessage;
  Uri? lastAuthorizationUri;
  List<FishMcpToolInfo> tools = const [];
  String? ttsToolName;
  bool drama3Supported = false;
  DateTime? lastDiscoveryAt;
  FishMcpException? lastError;
  Duration? lastGenerationLatency;
  Map<String, dynamic>? _lastRequestSummary;
  Map<String, dynamic>? _lastResultSummary;

  final http.Client _downloadClient;
  final Future<Directory> Function() _temporaryDirectory;
  final bool _persistDiagnostics;
  int _connectionGeneration = 0;

  McpClient? _client;
  _FishMcpPendingAuthorization? _pendingAuthorization;
  bool _disposed = false;

  bool _isCurrent(int generation) =>
      !_disposed && generation == _connectionGeneration;

  void _ensureCurrent(int generation, McpClient client) {
    if (!_isCurrent(generation) || !identical(client, _client)) {
      throw FishMcpException(
        stage: 'cancelled',
        code: 'connection_changed',
        message: '连接已改变，已丢弃旧请求的语音；不会重新生成。',
      );
    }
  }

  bool get isReady =>
      state == FishMcpConnectionState.toolsDiscovered && ttsToolName != null;

  FishMcpToolInfo? get selectedTtsTool {
    for (final tool in tools) {
      if (tool.name == ttsToolName) return tool;
    }
    return null;
  }

  String get diagnosticReport => const JsonEncoder.withIndent('  ').convert(
    redactFishMcpValue({
      'endpoint': endpoint,
      'state': state.name,
      'tts_tool': ttsToolName,
      'discovered_at': lastDiscoveryAt?.toIso8601String(),
      'drama3_listed_in_schema': drama3Supported,
      'local_input_schema_validation': false,
      'tools': tools.map((tool) => tool.toJson()).toList(),
      'last_request': _lastRequestSummary,
      'last_result': _lastResultSummary,
      'last_error': lastError?.toJson(),
      'last_generation_ms': lastGenerationLatency?.inMilliseconds,
    }),
  );

  Future<void> _saveDiagnostics() async {
    if (!_persistDiagnostics || _disposed) return;
    try {
      final directory = await _temporaryDirectory();
      await File('${directory.path}/fish_mcp_diagnostics.json')
          .writeAsString(diagnosticReport, flush: true);
    } on Object {
      // Diagnostics must not fail a successful request or start a retry.
    }
  }

  void _recordError(FishMcpException error) {
    lastError = error;
    errorMessage = error.toString();
    RuntimeLog.instance.warning('Fish MCP', error.toString());
    if (!_disposed) notifyListeners();
    unawaited(_saveDiagnostics());
  }

  String get statusLabel => switch (state) {
    FishMcpConnectionState.disconnected => '未连接',
    FishMcpConnectionState.connecting => '连接中',
    FishMcpConnectionState.authenticating => '等待 Fish Audio 授权',
    FishMcpConnectionState.connected => '已连接，待探测工具',
    FishMcpConnectionState.toolsDiscovered => '工具已探测',
    FishMcpConnectionState.error => '连接错误',
  };

  Future<void> connect({bool launchLogin = true}) async {
    final closing = disconnect(clearError: true);
    final generation = _connectionGeneration;
    await closing;
    if (!_isCurrent(generation)) return;
    final stored = await hasStoredCredentials();
    if (!_isCurrent(generation)) return;
    if (!stored) {
      await beginAuthorization(launchLogin: launchLogin);
      return;
    }
    await _connectWithStoredCredentials(launchLogin: launchLogin);
  }

  Future<void> _connectWithStoredCredentials({
    required bool launchLogin,
  }) async {
    final generation = _connectionGeneration;
    _setState(FishMcpConnectionState.connecting);
    final authProvider = _FishMcpOAuthProvider(
      isCurrent: () => _isCurrent(generation),
      onAuthorizationUrl: (uri) async {
        if (!_isCurrent(generation)) return;
        lastAuthorizationUri = uri;
        _setState(FishMcpConnectionState.authenticating);
      },
    );
    final client = McpClient(
      const Implementation(name: 'agent-atelier-r', version: '1.0.4.1'),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse(endpoint),
      opts: StreamableHttpClientTransportOptions(
        authProvider: authProvider,
        oauthUriValidator: (uri, _) =>
            uri.scheme == 'https' &&
            (uri.host == 'api.fish.audio' || uri.host.endsWith('.fish.audio')),
      ),
    );
    _client = client;
    try {
      await client.connect(transport);
      if (!_isCurrent(generation) || !identical(client, _client)) {
        await client.close();
        return;
      }
      _setState(FishMcpConnectionState.connected);
      await discoverTools();
    } on UnauthorizedError catch (cause) {
      if (!_isCurrent(generation) || !identical(client, _client)) return;
      // mcp_dart starts OAuth discovery and invokes redirectToAuthorizationUrl.
      // The connection is intentionally left unauthenticated until the app
      // receives the deep-link callback and the user retries connection.
      errorMessage = _safeError(cause);
      await beginAuthorization(launchLogin: launchLogin);
    } on Object catch (cause) {
      if (!_isCurrent(generation) || !identical(client, _client)) return;
      if (!identical(cause, lastError)) {
        _recordError(FishMcpException.fromCause(cause, stage: 'connection'));
      }
      _setState(FishMcpConnectionState.error);
    }
  }

  /// Registers a public PKCE client (once) and opens the official browser
  /// authorization page. Registration happens only after the user explicitly
  /// taps the connect button; startup never creates a remote client.
  Future<void> beginAuthorization({bool launchLogin = true}) async {
    final generation = _connectionGeneration;
    try {
      _setState(FishMcpConnectionState.connecting);
      final clientId = await _registeredClientId();
      if (!_isCurrent(generation)) return;
      final verifier = _randomUrlSafe(64);
      final challengeBytes = await Sha256().hash(utf8.encode(verifier));
      if (!_isCurrent(generation)) return;
      final challenge = base64UrlEncode(challengeBytes.bytes)
          .replaceAll('=', '');
      final stateValue = _randomUrlSafe(32);
      _pendingAuthorization = _FishMcpPendingAuthorization(
        clientId: clientId,
        codeVerifier: verifier,
        state: stateValue,
      );
      final authorizationUri = Uri.parse(_authorizeEndpoint).replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': clientId,
          'redirect_uri': callbackUri,
          'scope': 'mcp',
          'state': stateValue,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'resource': endpoint,
        },
      );
      lastAuthorizationUri = authorizationUri;
      _setState(FishMcpConnectionState.authenticating);
      if (launchLogin) {
        final opened = await launchUrl(
          authorizationUri,
          mode: LaunchMode.externalApplication,
        );
        if (!_isCurrent(generation)) return;
        if (!opened) errorMessage = '无法打开 Fish Audio 授权页面，请手动打开授权地址。';
      }
    } on Object catch (cause) {
      if (!_isCurrent(generation)) return;
      errorMessage = _safeError(cause);
      _setState(FishMcpConnectionState.error);
    }
  }

  Future<void> discoverTools() async {
    final client = _client;
    if (client == null) {
      throw FishMcpException(
        stage: 'discovery',
        code: 'not_connected',
        message: 'MCP 尚未连接，请先登录并读取工具列表。',
      );
    }
    final generation = _connectionGeneration;
    tools = const [];
    ttsToolName = null;
    drama3Supported = false;
    lastDiscoveryAt = null;
    errorMessage = null;
    _setState(FishMcpConnectionState.connected);
    try {
      final discovered = <FishMcpToolInfo>[];
      final cursors = <String>{};
      String? cursor;
      do {
        final result = await client.listTools(
          params: cursor == null ? null : ListToolsRequest(cursor: cursor),
          options: RequestOptions(timeout: const Duration(seconds: 30)),
        );
        discovered.addAll(
          result.tools.map(
            (tool) => FishMcpToolInfo(
              name: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema.toJson(),
            ),
          ),
        );
        cursor = result.nextCursor;
        if (cursor != null && (!cursors.add(cursor) || cursors.length > 100)) {
          throw FishMcpException(
            stage: 'discovery',
            code: 'invalid_cursor',
            message: '工具列表分页异常，已停止读取。',
          );
        }
      } while (cursor != null);
      if (generation != _connectionGeneration || !identical(client, _client)) {
        return;
      }
      tools = List.unmodifiable(discovered);
      final selected = selectFishMcpTtsTool(
        discovered
            .map(
              (tool) => FishMcpToolDefinition(
                name: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema,
              ),
            )
            .toList(),
      );
      ttsToolName = selected?.name;
      drama3Supported = _detectDrama3ForSelectedTool();
      lastDiscoveryAt = DateTime.now();
      errorMessage = ttsToolName == null ? '工具列表中没有可识别的 TTS 生成工具。' : null;
      lastError = null;
      _setState(FishMcpConnectionState.toolsDiscovered);
      RuntimeLog.instance.info(
        'Fish MCP',
        'tools/list 成功，工具数=${tools.length}，TTS=${ttsToolName ?? "未发现"}',
      );
      await _saveDiagnostics();
    } on Object catch (cause) {
      final error = cause is FishMcpException
          ? cause
          : FishMcpException.fromCause(cause, stage: 'discovery');
      if (generation == _connectionGeneration && identical(client, _client)) {
        _setState(FishMcpConnectionState.error);
        _recordError(error);
      }
      throw error;
    }
  }

  bool _detectDrama3ForSelectedTool() {
    final tool = selectedTtsTool;
    if (tool == null) return false;
    final properties = fishMcpSchemaProperties(tool.inputSchema);
    for (final key in const ['model', 'model_id', 'modelId']) {
      final schema = properties[key];
      if (schema is Map &&
          ((schema['enum'] is List &&
                  (schema['enum'] as List).contains('drama-3')) ||
              schema['const'] == 'drama-3')) {
        return true;
      }
    }
    return false;
  }

  /// Handles an app-link callback, exchanges the short-lived PKCE code, and
  /// reconnects with the persisted access token. The verifier and state stay
  /// in memory only and are never written to logs or ordinary backups.
  Future<void> handleRedirectUri(Uri uri) async {
    if (uri.scheme != 'fishmcp' || uri.host != 'oauth') return;
    final code = uri.queryParameters['code'];
    final stateValue = uri.queryParameters['state'];
    final error = uri.queryParameters['error'];
    if (error != null) {
      errorMessage = 'Fish Audio 授权失败：$error';
      _setState(FishMcpConnectionState.error);
      return;
    }
    if (code == null || stateValue == null) {
      errorMessage = 'Fish Audio 授权回调缺少 code 或 state。';
      _setState(FishMcpConnectionState.error);
      return;
    }
    final pending = _pendingAuthorization;
    if (pending == null || pending.state != stateValue) {
      errorMessage = 'Fish Audio 授权 state 不匹配，已拒绝回调。';
      _setState(FishMcpConnectionState.error);
      return;
    }
    final generation = _connectionGeneration;
    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'client_id': pending.clientId,
          'code': code,
          'redirect_uri': callbackUri,
          'code_verifier': pending.codeVerifier,
        },
      );
      if (!_isCurrent(generation) ||
          !identical(pending, _pendingAuthorization)) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Fish Audio token 交换失败 (${response.statusCode})');
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['access_token'] is! String) {
        throw StateError('Fish Audio token 响应格式无效');
      }
      final tokens = OAuthAuthorizationCodeTokens(
        accessToken: payload['access_token'] as String,
        refreshToken: payload['refresh_token'] as String?,
        expiresIn: (payload['expires_in'] as num?)?.toInt(),
        scope: payload['scope'] as String?,
      );
      await _FishMcpOAuthProvider.saveStoredTokens(
        tokens,
        isCurrent: () =>
            _isCurrent(generation) && identical(pending, _pendingAuthorization),
      );
      if (!_isCurrent(generation) ||
          !identical(pending, _pendingAuthorization)) {
        return;
      }
      _pendingAuthorization = null;
      await connect(launchLogin: false);
    } on Object catch (cause) {
      if (!_isCurrent(generation) ||
          !identical(pending, _pendingAuthorization)) {
        return;
      }
      errorMessage = _safeError(cause);
      _setState(FishMcpConnectionState.error);
    }
  }

  Future<String> synthesize({
    required String text,
    String? voice,
    String? model,
    String language = 'ja',
    String format = 'mp3',
    double speed = 1.0,
  }) async {
    var stage = 'preflight';
    var submitted = false;
    final generation = _connectionGeneration;
    _lastRequestSummary = null;
    _lastResultSummary = null;
    lastGenerationLatency = null;
    try {
      final client = _client;
      final tool = selectedTtsTool;
      if (!isReady || client == null || tool == null) {
        throw FishMcpException(
          stage: stage,
          code: 'not_ready',
          message: 'Fish MCP 尚未完成 tools/list，请先在语音设置连接并读取工具。',
        );
      }
      stage = 'parameters';
      final omitted = <String, String>{};
      final arguments = buildFishMcpTtsArguments(
        tool: FishMcpToolDefinition(
          name: tool.name,
          description: tool.description,
          inputSchema: tool.inputSchema,
        ),
        text: text,
        voice: voice,
        model: model,
        language: language,
        format: format,
        speed: speed,
        onOmittedOptionalField: (field, explanation) {
          omitted[field] = explanation;
        },
      );
      _lastRequestSummary = {
        'tool': tool.name,
        'argument_names': arguments.keys.toList(),
        'text_utf8_bytes': utf8.encode(text).length,
        'requested_model': ?model,
        if (omitted.isNotEmpty) 'omitted_optional_fields': omitted,
        'model_sent':
            arguments.containsKey('model') ||
            arguments.containsKey('model_id') ||
            arguments.containsKey('modelId'),
      };
      _lastResultSummary = null;
      lastError = null;
      errorMessage = null;
      stage = 'transport';
      submitted = true;
      final timer = Stopwatch()..start();
      late final CallToolResult result;
      try {
        // A generation request is submitted only once. A transport timeout
        // cannot establish whether the server already consumed credits.
        result = await client.callTool(
          CallToolRequest(name: tool.name, arguments: arguments),
          options: RequestOptions(timeout: const Duration(seconds: 90)),
        );
      } finally {
        lastGenerationLatency = timer.elapsed;
      }
      _ensureCurrent(generation, client);
      final structured = result.structuredContentJson?.toJson();
      _lastResultSummary = {
        'is_error': result.isError,
        'content_types': result.content.map((item) => item.type).toList(),
        'structured_type': structured.runtimeType.toString(),
        if (structured is Map) 'structured_keys': structured.keys.toList(),
      };
      stage = 'result';
      if (result.isError) {
        throw FishMcpException.fromToolResult(result, stage: stage);
      }
      stage = 'audio_parse';
      final audio = parseFishMcpAudioResult(result);
      Uint8List? bytes = audio.bytes;
      if (audio.uri != null) {
        stage = 'audio_download';
        bytes = await _downloadAudio(audio.uri!);
      }
      _ensureCurrent(generation, client);
      stage = 'audio_validate';
      if (bytes == null || bytes.isEmpty) {
        throw FishMcpException(
          stage: stage,
          code: 'empty_audio',
          message: '工具返回了空音频。',
        );
      }
      final extension = detectAudioContainerExtension(bytes);
      if (extension == null) {
        throw FishMcpException(
          stage: stage,
          code: 'invalid_audio',
          message: '工具结果不是可识别的音频文件；已停止播放和自动重试。',
        );
      }
      stage = 'audio_file';
      final directory = await _temporaryDirectory();
      _ensureCurrent(generation, client);
      final file = File(
        '${directory.path}/fish_mcp_${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!_isCurrent(generation) || !identical(client, _client)) {
        await file.delete();
        _ensureCurrent(generation, client);
      }
      RuntimeLog.instance.info(
        'Fish MCP',
        '音频已获取，tool=${tool.name}, format=$extension, bytes=${bytes.length}, generation_ms=${lastGenerationLatency?.inMilliseconds}',
      );
      await _saveDiagnostics();
      if (!_disposed) notifyListeners();
      return file.path;
    } on Object catch (cause) {
      final error = FishMcpException.fromCause(
        cause,
        stage: stage,
        outcomeUnknown: submitted && stage == 'transport',
        generationSubmitted: submitted,
      );
      if (generation == _connectionGeneration && !_disposed) {
        _recordError(error);
      }
      throw error;
    }
  }

  Future<Uint8List> _downloadAudio(Uri initialUri) async {
    const maximumBytes = 64 * 1024 * 1024;
    final policy = FishMcpAudioUrlPolicy();
    var uri = initialUri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      policy.validate(uri);
      final abort = Completer<void>();
      final timer = Timer(const Duration(seconds: 45), () => abort.complete());
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers['Accept'] = 'audio/*, application/octet-stream';
      try {
        final response = await _downloadClient.send(request);
        final requestId =
            response.headers['x-request-id'] ??
            response.headers['request-id'] ??
            response.headers['x-correlation-id'];
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers['location'];
          // Do not send OAuth credentials to the audio host or follow an
          // arbitrary redirect. Check the next destination before issuing GET.
          await response.stream.drain<void>();
          if (location == null || redirects == 5) {
            throw FishMcpException(
              stage: 'audio_download',
              code: 'invalid_redirect',
              status: response.statusCode,
              message: '音频地址重定向异常。',
              requestId: requestId,
            );
          }
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.drain<void>();
          throw FishMcpException(
            stage: 'audio_download',
            code: 'audio_http_error',
            status: response.statusCode,
            message: '音频下载失败（HTTP ${response.statusCode}）；不会再次提交生成。',
            requestId: requestId,
          );
        }
        final contentType = response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        if (contentType != null &&
            !contentType.startsWith('audio/') &&
            contentType != 'application/octet-stream' &&
            contentType != 'binary/octet-stream') {
          await response.stream.drain<void>();
          throw FishMcpException(
            stage: 'audio_download',
            code: 'invalid_content_type',
            message: '音频地址返回了 $contentType，已拒绝播放。',
            requestId: requestId,
          );
        }
        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > maximumBytes) {
          if (!abort.isCompleted) abort.complete();
          throw FishMcpException(
            stage: 'audio_download',
            code: 'audio_too_large',
            message: '音频文件超过 64 MB，已停止下载。',
          );
        }
        final output = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (output.length + chunk.length > maximumBytes) {
            if (!abort.isCompleted) abort.complete();
            throw FishMcpException(
              stage: 'audio_download',
              code: 'audio_too_large',
              message: '音频文件超过 64 MB，已停止下载。',
            );
          }
          output.add(chunk);
        }
        return output.takeBytes();
      } finally {
        timer.cancel();
      }
    }
    throw FishMcpException(
      stage: 'audio_download',
      code: 'invalid_redirect',
      message: '音频重定向次数过多。',
    );
  }

  Future<void> disconnect({bool clearError = false}) async {
    _connectionGeneration++;
    final client = _client;
    _client = null;
    _pendingAuthorization = null;
    lastAuthorizationUri = null;
    tools = const [];
    ttsToolName = null;
    drama3Supported = false;
    lastDiscoveryAt = null;
    if (clearError) {
      errorMessage = null;
      lastError = null;
    }
    _setState(FishMcpConnectionState.disconnected);
    try {
      await client?.close();
    } on Object {
      // Closing a failed OAuth transport is best-effort.
    }
  }

  Future<void> logout() async {
    await disconnect(clearError: true);
    await _FishMcpOAuthProvider.queueCredentialWrite(
      () => _storage.delete(key: _credentialKey),
    );
    await _storage.delete(key: _clientIdKey);
    _pendingAuthorization = null;
  }

  Future<bool> hasStoredCredentials() async =>
      (await _storage.read(key: _credentialKey))?.trim().isNotEmpty == true;

  static Future<OAuthTokens?> _readValidTokens({
    required bool Function() isCurrent,
  }) async {
    final raw = await _storage.read(key: _credentialKey);
    if (!isCurrent()) return null;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['accessToken'] is! String) return null;
      final expiresAt = json['expiresAt'] as String?;
      final expiry = expiresAt == null ? null : DateTime.tryParse(expiresAt);
      if (expiry == null ||
          expiry.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
        return OAuthTokens(
          accessToken: json['accessToken'] as String,
          refreshToken: json['refreshToken'] as String?,
        );
      }
      final refreshToken = json['refreshToken'] as String?;
      final clientId = await _storage.read(key: _clientIdKey);
      if (!isCurrent()) return null;
      if (refreshToken == null || clientId == null || clientId.isEmpty) {
        return null;
      }
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': refreshToken,
        },
      );
      if (!isCurrent()) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['access_token'] is! String) return null;
      final tokens = OAuthAuthorizationCodeTokens(
        accessToken: payload['access_token'] as String,
        refreshToken: payload['refresh_token'] as String? ?? refreshToken,
        expiresIn: (payload['expires_in'] as num?)?.toInt(),
        scope: payload['scope'] as String?,
      );
      await _FishMcpOAuthProvider.saveStoredTokens(
        tokens,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return null;
      return OAuthTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } on Object {
      return null;
    }
  }

  Future<String> _registeredClientId() async {
    final existing = await _storage.read(key: _clientIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();
    final response = await http.post(
      Uri.parse(_registerEndpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_name': 'AgentAtelierR',
        'redirect_uris': [callbackUri],
        'grant_types': ['authorization_code', 'refresh_token'],
        'response_types': ['code'],
        'token_endpoint_auth_method': 'none',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Fish Audio OAuth 客户端注册失败 (${response.statusCode})');
    }
    final payload = jsonDecode(response.body);
    final clientId = payload is Map ? payload['client_id'] : null;
    if (clientId is! String || clientId.trim().isEmpty) {
      throw StateError('Fish Audio OAuth 注册响应缺少 client_id');
    }
    await _storage.write(key: _clientIdKey, value: clientId.trim());
    return clientId.trim();
  }

  static String _randomUrlSafe(int length) {
    final bytes = List<int>.generate(length, (_) => 0);
    final random = Random.secure();
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _safeError(Object cause) => redactFishMcpText(cause.toString());

  void _setState(FishMcpConnectionState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    _downloadClient.close();
    super.dispose();
  }
}

class _FishMcpPendingAuthorization {
  const _FishMcpPendingAuthorization({
    required this.clientId,
    required this.codeVerifier,
    required this.state,
  });

  final String clientId;
  final String codeVerifier;
  final String state;
}

class _FishMcpOAuthProvider implements OAuthAuthorizationCodeProvider {
  _FishMcpOAuthProvider({
    required this.onAuthorizationUrl,
    required this.isCurrent,
  });

  final Future<void> Function(Uri uri) onAuthorizationUrl;
  final bool Function() isCurrent;

  static Future<void> _credentialWriteTail = Future<void>.value();

  static Future<void> queueCredentialWrite(Future<void> Function() write) {
    final operation = _credentialWriteTail.then((_) => write());
    _credentialWriteTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  String get clientId => '';

  @override
  Uri get redirectUri => Uri.parse(FishMcpService.callbackUri);

  @override
  String? get clientSecret => null;

  @override
  List<String> get scopes => const ['mcp'];

  @override
  Future<void> redirectToAuthorizationUrl(Uri authorizationUri) =>
      onAuthorizationUrl(authorizationUri);

  @override
  Future<void> redirectToAuthorization() async {}

  @override
  Future<OAuthTokens?> tokens() async {
    return FishMcpService._readValidTokens(isCurrent: isCurrent);
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    await saveStoredTokens(tokens, isCurrent: isCurrent);
  }

  static Future<void> saveStoredTokens(
    OAuthTokens tokens, {
    required bool Function() isCurrent,
  }) async {
    final payload = <String, dynamic>{
      'accessToken': tokens.accessToken,
      if (tokens.refreshToken != null) 'refreshToken': tokens.refreshToken,
      if (tokens is OAuthAuthorizationCodeTokens && tokens.expiresIn != null)
        'expiresAt': DateTime.now()
            .add(Duration(seconds: tokens.expiresIn!))
            .toUtc()
            .toIso8601String(),
      if (tokens is OAuthIssuerBoundAuthorizationCodeTokens)
        'issuer': tokens.authorizationServerIssuer,
      if (tokens is OAuthIssuerBoundAuthorizationCodeTokens)
        'resource': tokens.resource.toString(),
    };
    await queueCredentialWrite(() async {
      if (!isCurrent()) return;
      await FishMcpService._storage.write(
        key: FishMcpService._credentialKey,
        value: jsonEncode(payload),
      );
    });
  }
}
