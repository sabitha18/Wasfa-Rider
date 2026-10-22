import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config.dart';

/// Thrown by ApiClient on any failed request. Catch this in
/// repositories/ViewModels to show a message to the user.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Wraps Dio with auth-token injection + consistent error mapping.
/// This is the ONLY class that should talk to the network directly —
/// repositories call ApiClient, never Dio/http directly.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ));
    _dio.httpClientAdapter = _newAdapter();

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // TODO: if backend uses refresh tokens, attempt refresh here on 401
        // before giving up and forcing logout.
        // CLIENT-REPORTED (2026-08-18): "Could not reach the server" was
        // showing up right after unlocking the phone, even with a
        // genuinely fine internet connection throughout the whole time.
        // Root cause: Dart's HttpClient (which Dio uses under the hood)
        // reuses a persistent keep-alive TCP connection by default. While
        // the screen is off and the app goes idle, the OS or a NAT/
        // carrier timeout can silently kill that connection in the
        // background — the client has no way to know until it actually
        // tries to reuse it, which happens to be exactly the first
        // request fired right on unlock. That one attempt fails with a
        // low-level connection error even though the network itself is
        // completely fine; a fresh connection on the very next attempt
        // works. Retry once, transparently, specifically for this class
        // of error — this fixes the actual mechanism, rather than just
        // hiding the symptom from the user after the fact.
        // CLIENT-REPORTED (2026-10-22) follow-up: drivers still hit
        // "Could not reach the server" and only an app restart cleared it.
        // The single instant retry above went through the SAME Dart
        // HttpClient, whose pooled sockets were already dead after a
        // network switch (Wi-Fi <-> 4G, tower handover, screen-off idle),
        // so the retry failed too and the app stayed stuck. An app restart
        // works only because it creates a brand-new HttpClient — so now we
        // do exactly that in code: throw away the old client, wait briefly
        // for the radio to settle, and retry on a fresh one (up to
        // _maxConnRetries times).
        final isConnectionError = error.type == DioExceptionType.connectionError;
        final isRetryAttempt = error.requestOptions.extra[_retryFlag] == true;
        if (isConnectionError && !isRetryAttempt) {
          for (var attempt = 1; attempt <= _maxConnRetries; attempt++) {
            resetConnection(reason: 'connectionError on '
                '${error.requestOptions.method} ${error.requestOptions.path} (retry $attempt/$_maxConnRetries)');
            await Future.delayed(Duration(milliseconds: 800 * attempt));
            try {
              final retryOptions = error.requestOptions;
              retryOptions.extra[_retryFlag] = true;
              // A FormData body can only be sent once — clone it so
              // multipart uploads (POD photo, building photos) can retry.
              if (retryOptions.data is FormData) {
                retryOptions.data = (retryOptions.data as FormData).clone();
              }
              final response = await _dio.fetch(retryOptions);
              debugPrint('[ApiClient] retry $attempt succeeded for ${retryOptions.method} ${retryOptions.path}');
              handler.resolve(response);
              return;
            } on DioException catch (e) {
              if (e.type != DioExceptionType.connectionError) {
                // Reached the server this time but got a real error back
                // (e.g. 422) — pass THAT on, not the stale connection error.
                handler.next(e);
                return;
              }
              debugPrint('[ApiClient] retry $attempt failed: ${e.error ?? e.message}');
            } catch (e) {
              debugPrint('[ApiClient] retry $attempt failed: $e');
            }
          }
        }
        handler.next(error);
      },
    ));

    // Every request/response body — OTP codes, civil ID, IBAN, cash
    // amounts, base64 signatures, all of it — went to logcat on every
    // build, release included. Debug/profile only now; a release build
    // never adds this interceptor at all.
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: false,
        responseHeader: false,
      ));
    }
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;

  static const _retryFlag = 'retriedAfterConnectionError';
  static const _maxConnRetries = 2;
  DateTime? _lastReset;

  /// Fresh Dart HttpClient. idleTimeout is 5s (Dart default is 15s) so
  /// idle keep-alive sockets are closed by us before a carrier/NAT can
  /// silently kill them while the driver is idle or the screen is off.
  IOHttpClientAdapter _newAdapter() => IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.idleTimeout = const Duration(seconds: 5);
          client.connectionTimeout = const Duration(seconds: 15);
          return client;
        },
      );

  /// Drops every pooled connection and installs a brand-new HttpClient —
  /// the same thing an app restart does, without the restart. Called on
  /// a connection error (before retrying) and when the app resumes from
  /// background. Debounced: several requests failing at the same moment
  /// (orders poll + batch poll) only trigger one reset, so a request
  /// already running on the new client is never killed by a second reset.
  void resetConnection({String reason = ''}) {
    final now = DateTime.now();
    if (_lastReset != null && now.difference(_lastReset!) < const Duration(seconds: 2)) return;
    _lastReset = now;
    debugPrint('[ApiClient] resetting HTTP connection${reason.isEmpty ? '' : ' — $reason'}');
    final old = _dio.httpClientAdapter;
    _dio.httpClientAdapter = _newAdapter();
    try {
      old.close(force: true);
    } catch (_) {}
  }
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'wasfa_rider_auth_token';

  // ── Token management ────────────────────────────────────────────
  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> readToken() => _storage.read(key: _tokenKey);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
  Future<bool> get hasToken async => (await readToken()) != null;

  // ── Verb helpers ──────────────────────────────────────────────
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, {Object? data}) =>
      _send(() => _dio.post(path, data: data));

  Future<Map<String, dynamic>> patch(String path, {Object? data}) =>
      _send(() => _dio.patch(path, data: data));

  Future<Map<String, dynamic>> delete(String path, {Object? data}) =>
      _send(() => _dio.delete(path, data: data));

  Future<Map<String, dynamic>> postMultipart(String path, FormData form) =>
      _send(() => _dio.post(path, data: form));

  Future<Map<String, dynamic>> _send(Future<Response> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      // Some backends wrap arrays at top level — normalize to a map.
      return {'data': data};
    } on DioException catch (e) {
      // Real underlying cause (SocketException / failed host lookup /
      // handshake etc.) so logcat shows WHY, not just the friendly text.
      // No request/response bodies here — safe for release builds.
      debugPrint('[ApiClient] ${e.type.name} ${e.requestOptions.method} ${e.requestOptions.path} '
          '(${e.response?.statusCode ?? 'no response'}): ${e.error ?? e.message}');
      throw ApiException(_messageFor(e), statusCode: e.response?.statusCode);
    }
  }

  String _messageFor(DioException e) {
    final serverMsg = e.response?.data is Map
        ? (e.response?.data['message'] ?? e.response?.data['error'] ?? e.response?.data['msg'])
        : null;
    if (serverMsg is String) return serverMsg;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your internet connection.';
      default:
        return 'Something went wrong (${e.response?.statusCode ?? 'no response'}).';
    }
  }
}
