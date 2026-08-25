import 'package:dio/dio.dart';
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
        final isConnectionError = error.type == DioExceptionType.connectionError;
        final alreadyRetried = error.requestOptions.extra['retriedAfterConnectionError'] == true;
        if (isConnectionError && !alreadyRetried) {
          try {
            final retryOptions = error.requestOptions;
            retryOptions.extra['retriedAfterConnectionError'] = true;
            final response = await _dio.fetch(retryOptions);
            handler.resolve(response);
            return;
          } catch (_) {
            // The retry itself failed too — this is no longer just a
            // stale-connection blip, so fall through and let the
            // original error propagate normally.
          }
        }
        handler.next(error);
      },
    ));

    // Prints every request/response/error. Remove or wrap in
    // `if (kDebugMode)` before shipping a release build.
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      requestHeader: false,
      responseHeader: false,
    ));
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;
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
      throw ApiException(_messageFor(e), statusCode: e.response?.statusCode);
    }
  }

  String _messageFor(DioException e) {
    final serverMsg = e.response?.data is Map
        ? (e.response?.data['message'] ?? e.response?.data['error'])
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
