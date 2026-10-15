import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cryptography/cryptography.dart';
import 'package:url_launcher/url_launcher.dart';

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
  FishMcpService._();

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

  McpClient? _client;
  _FishMcpPendingAuthorization? _pendingAuthorization;
  bool _disposed = false;

  bool get isReady =>
      state == FishMcpConnectionState.toolsDiscovered && ttsToolName != null;

  String get statusLabel => switch (state) {
    FishMcpConnectionState.disconnected => '未连接',
    FishMcpConnectionState.connecting => '连接中',
    FishMcpConnectionState.authenticating => '等待 Fish Audio 授权',
    FishMcpConnectionState.connected => '已连接，待探测工具',
    FishMcpConnectionState.toolsDiscovered => '工具已探测',
    FishMcpConnectionState.error => '连接错误',
  };

  Future<void> connect({bool launchLogin = true}) async {
    await disconnect(clearError: true);
    if (!await hasStoredCredentials()) {
      await beginAuthorization(launchLogin: launchLogin);
      return;
    }
    await _connectWithStoredCredentials(launchLogin: launchLogin);
  }

  Future<void> _connectWithStoredCredentials({
    required bool launchLogin,
  }) async {
    _setState(FishMcpConnectionState.connecting);
    final authProvider = _FishMcpOAuthProvider(
      onAuthorizationUrl: (uri) async {
        lastAuthorizationUri = uri;
        _setState(FishMcpConnectionState.authenticating);
      },
    );
    final client = McpClient(
      const Implementation(name: 'agent-atelier-r', version: '1.0.4'),
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
      _setState(FishMcpConnectionState.connected);
      await discoverTools();
    } on UnauthorizedError catch (cause) {
      // mcp_dart starts OAuth discovery and invokes redirectToAuthorizationUrl.
      // The connection is intentionally left unauthenticated until the app
      // receives the deep-link callback and the user retries connection.
      errorMessage = cause.toString();
      await beginAuthorization(launchLogin: launchLogin);
    } on Object catch (cause) {
      errorMessage = _safeError(cause);
      _setState(FishMcpConnectionState.error);
    }
  }

  /// Registers a public PKCE client (once) and opens the official browser
  /// authorization page. Registration happens only after the user explicitly
  /// taps the connect button; startup never creates a remote client.
  Future<void> beginAuthorization({bool launchLogin = true}) async {
    try {
      _setState(FishMcpConnectionState.connecting);
      final clientId = await _registeredClientId();
      final verifier = _randomUrlSafe(64);
      final challengeBytes = await Sha256().hash(utf8.encode(verifier));
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
        if (!opened) errorMessage = '无法打开 Fish Audio 授权页面，请手动打开授权地址。';
      }
    } on Object catch (cause) {
      errorMessage = _safeError(cause);
      _setState(FishMcpConnectionState.error);
    }
  }

  Future<void> discoverTools() async {
    final client = _client;
    if (client == null) throw StateError('MCP 尚未连接');
    final result = await client.listTools();
    final discovered = [
      for (final tool in result.tools)
        FishMcpToolInfo(
          name: tool.name,
          description: tool.description,
          inputSchema: tool.inputSchema.toJson(),
        ),
    ];
    tools = List.unmodifiable(discovered);
    ttsToolName = _selectTtsTool(discovered);
    drama3Supported = _detectDrama3(discovered);
    lastDiscoveryAt = DateTime.now();
    errorMessage = ttsToolName == null ? 'MCP 未提供可识别的 TTS 工具。' : null;
    _setState(FishMcpConnectionState.toolsDiscovered);
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
      await _FishMcpOAuthProvider.saveStoredTokens(tokens);
      _pendingAuthorization = null;
      await connect(launchLogin: false);
    } on Object catch (cause) {
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
    if (!isReady) {
      throw StateError('Fish MCP 尚未完成 tools/list，已阻止语音生成。');
    }
    final client = _client;
    final tool = tools.firstWhere((candidate) => candidate.name == ttsToolName);
    final properties =
        (tool.inputSchema['properties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final arguments = <String, dynamic>{};
    _putIfSupported(arguments, properties, const [
      'text',
      'input_text',
      'content',
    ], text);
    _putIfSupported(arguments, properties, const [
      'voice',
      'voice_id',
      'speaker',
      'reference_id',
    ], voice);
    _putIfSupported(arguments, properties, const ['model', 'model_id'], model);
    _putIfSupported(arguments, properties, const [
      'language',
      'lang',
    ], language);
    _putIfSupported(arguments, properties, const [
      'format',
      'output_format',
    ], format);
    _putIfSupported(arguments, properties, const [
      'speed',
      'prosody_speed',
    ], speed.clamp(0.5, 2.0));
    final result = await client!.callTool(
      CallToolRequest(name: tool.name, arguments: arguments),
    );
    if (result.isError) throw StateError('Fish MCP TTS 工具返回错误。');
    var audio = _extractAudio(result);
    if (audio == null) throw StateError('Fish MCP TTS 未返回可播放音频。');
    if (audio.uri != null) {
      final uri = audio.uri!;
      if (uri.scheme != 'https' || !_isAllowedAudioHost(uri.host)) {
        throw StateError('Fish MCP 返回了不受信任的音频地址。');
      }
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Fish MCP 音频地址返回 ${response.statusCode}。');
      }
      audio = _FishMcpAudio(
        Uint8List.fromList(response.bodyBytes),
        response.headers['content-type'] ?? audio.mimeType,
      );
    }
    final directory = await getTemporaryDirectory();
    final extension = audio.mimeType.contains('wav')
        ? 'wav'
        : audio.mimeType.contains('ogg')
        ? 'ogg'
        : 'mp3';
    final file =
        '${directory.path}/fish_mcp_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final bytes = audio.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fish MCP 返回了空音频。');
    }
    await File(file).writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> disconnect({bool clearError = false}) async {
    try {
      await _client?.close();
    } on Object {
      // Closing a failed OAuth transport is best-effort.
    }
    _client = null;
    tools = const [];
    ttsToolName = null;
    drama3Supported = false;
    if (clearError) errorMessage = null;
    _setState(FishMcpConnectionState.disconnected);
  }

  Future<void> logout() async {
    await disconnect(clearError: true);
    await _storage.delete(key: _credentialKey);
    await _storage.delete(key: _clientIdKey);
    _pendingAuthorization = null;
  }

  Future<bool> hasStoredCredentials() async =>
      (await _storage.read(key: _credentialKey))?.trim().isNotEmpty == true;

  static Future<OAuthTokens?> _readValidTokens() async {
    final raw = await _storage.read(key: _credentialKey);
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
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['access_token'] is! String) return null;
      final tokens = OAuthAuthorizationCodeTokens(
        accessToken: payload['access_token'] as String,
        refreshToken: payload['refresh_token'] as String? ?? refreshToken,
        expiresIn: (payload['expires_in'] as num?)?.toInt(),
        scope: payload['scope'] as String?,
      );
      await _FishMcpOAuthProvider.saveStoredTokens(tokens);
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

  void _putIfSupported(
    Map<String, dynamic> target,
    Map<String, dynamic> properties,
    List<String> names,
    Object? value,
  ) {
    if (value == null) return;
    for (final name in names) {
      if (properties.containsKey(name)) {
        target[name] = value;
        return;
      }
    }
  }

  static String? _selectTtsTool(List<FishMcpToolInfo> values) {
    final candidates = values.where((tool) {
      final haystack = '${tool.name} ${tool.description ?? ''}'.toLowerCase();
      return haystack.contains('tts') ||
          haystack.contains('text-to-speech') ||
          haystack.contains('speech synthesis');
    }).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aScore = a.name.toLowerCase().contains('synth') ? 1 : 0;
      final bScore = b.name.toLowerCase().contains('synth') ? 1 : 0;
      return bScore.compareTo(aScore);
    });
    return candidates.first.name;
  }

  static bool _detectDrama3(List<FishMcpToolInfo> values) => values.any(
    (tool) => '${tool.name} ${tool.description} ${jsonEncode(tool.inputSchema)}'
        .toLowerCase()
        .contains('drama-3'),
  );

  static _FishMcpAudio? _extractAudio(CallToolResult result) {
    for (final content in result.content) {
      if (content is AudioContent) {
        return _FishMcpAudio(
          Uint8List.fromList(base64Decode(content.data)),
          content.mimeType,
        );
      }
      if (content is TextContent) {
        final value = content.text.trim();
        final uri = Uri.tryParse(value);
        if (uri != null &&
            uri.scheme == 'https' &&
            _isAllowedAudioHost(uri.host)) {
          return _FishMcpAudio(null, 'audio/mpeg', uri: uri);
        }
        try {
          final decoded = jsonDecode(value);
          final audio = _extractFromJson(decoded);
          if (audio != null) return audio;
        } on Object {
          // Text is not an audio payload.
        }
      }
    }
    final structured = result.structuredContent;
    return _extractFromJson(structured);
  }

  static _FishMcpAudio? _extractFromJson(Object? value) {
    if (value is Map) {
      final mime = value['mimeType'] ?? value['mime_type'] ?? 'audio/mpeg';
      for (final key in const ['data', 'audio', 'audio_base64', 'base64']) {
        final raw = value[key];
        if (raw is String && raw.trim().isNotEmpty) {
          try {
            return _FishMcpAudio(
              Uint8List.fromList(base64Decode(raw)),
              '$mime',
            );
          } on Object {
            // Try another field.
          }
        }
      }
      for (final key in const [
        'url',
        'audio_url',
        'audioUrl',
        'download_url',
      ]) {
        final raw = value[key];
        final uri = raw is String ? Uri.tryParse(raw) : null;
        if (uri != null &&
            uri.scheme == 'https' &&
            _isAllowedAudioHost(uri.host)) {
          return _FishMcpAudio(null, 'audio/mpeg', uri: uri);
        }
      }
      for (final key in const ['result', 'output', 'audio_data']) {
        final nested = _extractFromJson(value[key]);
        if (nested != null) return nested;
      }
    }
    if (value is List) {
      for (final item in value) {
        final nested = _extractFromJson(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static bool _isAllowedAudioHost(String host) =>
      host == 'api.fish.audio' || host.endsWith('.fish.audio');

  String _safeError(Object cause) => cause.toString().replaceAll(
    RegExp(r'(Bearer\s+)[^\s]+', caseSensitive: false),
    r'\1[REDACTED]',
  );

  void _setState(FishMcpConnectionState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}

class _FishMcpAudio {
  const _FishMcpAudio(this.bytes, this.mimeType, {this.uri});
  final Uint8List? bytes;
  final String mimeType;
  final Uri? uri;
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
  _FishMcpOAuthProvider({required this.onAuthorizationUrl});

  final Future<void> Function(Uri uri) onAuthorizationUrl;

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
    return FishMcpService._readValidTokens();
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    await saveStoredTokens(tokens);
  }

  static Future<void> saveStoredTokens(OAuthTokens tokens) async {
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
    await FishMcpService._storage.write(
      key: FishMcpService._credentialKey,
      value: jsonEncode(payload),
    );
  }
}
