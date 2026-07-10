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
