import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? _buildDio();

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.fanos.example/api/v1',
  );

  final Dio _dio;

  /// Local uploads belong to the configured backend, including on physical phones.
  static String resolveMediaUrl(String value, {String backend = baseUrl}) {
    final uri = Uri.tryParse(value);
    final api = Uri.parse(backend);
    if (uri == null) return value;
    if (value.startsWith('/api/') || value.startsWith('/media/')) {
      return api.resolve(value).toString();
    }
    if (const {'localhost', '127.0.0.1', '::1'}.contains(uri.host) &&
        uri.path.startsWith('/media/')) {
      return api
          .replace(path: uri.path, query: uri.query.isEmpty ? null : uri.query)
          .toString();
    }
    return value;
  }

  dynamic _resolveMedia(dynamic data) {
    if (data is String) return resolveMediaUrl(data);
    if (data is List) return data.map(_resolveMedia).toList();
    if (data is Map<String, dynamic>) {
      return data.map((key, value) => MapEntry(key, _resolveMedia(value)));
    }
    return data;
  }

  String? _accessToken;

  void setAccessToken(String token) => _accessToken = token;

  void clearAccessToken() => _accessToken = null;

  Options get _options => Options(
    headers: {
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    },
  );

  static Dio _buildDio() => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
    ),
  );

  Future<dynamic> getData(String path, {Map<String, dynamic>? query}) async {
    return _request(
      () => _dio.get<dynamic>(path, queryParameters: query, options: _options),
    );
  }

  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
  }) async {
    return _request(
      () => _dio.post<dynamic>(
        path,
        data: data,
        options: _options.copyWith(receiveTimeout: receiveTimeout),
      ),
    );
  }

  Future<dynamic> putData(String path, {Object? data}) async {
    return _request(
      () => _dio.put<dynamic>(path, data: data, options: _options),
    );
  }

  Future<dynamic> patchData(String path, {Object? data}) async {
    return _request(
      () => _dio.patch<dynamic>(path, data: data, options: _options),
    );
  }

  Future<dynamic> deleteData(String path, {Object? data}) async {
    return _request(
      () => _dio.delete<dynamic>(path, data: data, options: _options),
    );
  }

  Future<dynamic> _request(
    Future<Response<dynamic>> Function() operation,
  ) async {
    try {
      final response = await operation();
      return _unwrap(response.data);
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map<String, dynamic>) {
        throw ApiException(
          (body['error_code'] ?? 'HTTP_ERROR').toString(),
          (body['message'] ?? '网络请求失败，请稍后重试').toString(),
        );
      }
      throw const ApiException('NETWORK_ERROR', '网络连接失败，请检查服务地址');
    }
  }

  dynamic _unwrap(dynamic body) {
    if (body is! Map<String, dynamic>) {
      throw const ApiException('INVALID_RESPONSE', '服务返回格式异常');
    }
    final code = body['code'];
    if (code != 0) {
      throw ApiException(
        (body['error_code'] ?? 'UNKNOWN_ERROR').toString(),
        (body['message'] ?? '请求失败，请稍后重试').toString(),
      );
    }
    return _resolveMedia(body['data']);
  }
}

class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
