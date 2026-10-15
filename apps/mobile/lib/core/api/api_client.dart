import 'package:dio/dio.dart';

import 'token_store.dart';

class ApiClient {
  ApiClient({Dio? dio, this.tokenStore}) : _dio = dio ?? _buildDio();

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.fanos.example/api/v1',
  );

  final Dio _dio;
  final TokenStore? tokenStore;
  Future<void> _storageWork = Future.value();
  Future<void> _store(Future<void> Function() operation) {
    final result = _storageWork.then((_) => operation());
    _storageWork = result.catchError((Object _) {});
    return result;
  }

  String? _refreshToken;
  DateTime? _expiresAt;
  Future<void>? _refreshing;
  int _authGeneration = 0;
  bool isNewAccount = false;

  /// Local uploads belong to the configured backend, including on physical phones.
  static String resolveMediaUrl(String value, {String backend = baseUrl}) {
    final uri = Uri.tryParse(value);
    final api = Uri.parse(backend);
    if (uri == null) return value;
    if (value.startsWith('/api/') || value.startsWith('/media/')) {
      return api.resolve(value).toString();
    }
    final loopback = const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    final ownMedia = uri.host == api.host && uri.path.startsWith('/media/');
    if ((loopback &&
            (uri.path.startsWith('/media/') || uri.path.startsWith('/api/'))) ||
        ownMedia) {
      return api
          .replace(path: uri.path, query: uri.query.isEmpty ? null : uri.query)
          .toString();
    }
    return value;
  }

  dynamic _resolveMedia(dynamic data) {
    if (data is String) {
      return resolveMediaUrl(data, backend: _dio.options.baseUrl);
    }
    if (data is List) return data.map(_resolveMedia).toList();
    if (data is Map<String, dynamic>) {
      return data.map((key, value) => MapEntry(key, _resolveMedia(value)));
    }
    return data;
  }

  String? _accessToken;

  void setAccessToken(String token) => _accessToken = token;

  void clearAccessToken() {
    _authGeneration++;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
  }

  Future<void> saveAuthTokens(Map<String, dynamic> data) async {
    final generation = _authGeneration;
    final access = data['access_token'];
    if (access is! String || access.isEmpty) {
      throw const ApiException('INVALID_AUTH_RESPONSE', '登录服务返回格式异常');
    }
    final refresh = data['refresh_token'] as String?;
    final expiry = DateTime.now().add(
      Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3600),
    );
    await _store(() async {
      if (generation != _authGeneration) return;
      await tokenStore?.write({
        'access_token': access,
        'refresh_token': refresh,
        'expires_at': expiry.toIso8601String(),
      });
    });
    if (generation != _authGeneration) {
      throw const ApiException('AUTH_REQUIRED', '请重新登录');
    }
    _accessToken = access;
    _refreshToken = refresh;
    _expiresAt = expiry;
  }

  Future<bool> restoreAuthTokens() async {
    final data = await tokenStore?.read();
    if (data == null) return false;
    if (data['access_token'] is! String ||
        data['refresh_token'] is! String ||
        data['expires_at'] is! String) {
      await logout();
      return false;
    }
    _accessToken = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String;
    _expiresAt = DateTime.tryParse(data['expires_at'] as String);
    if (_accessToken?.isNotEmpty != true || _refreshToken?.isNotEmpty != true) {
      await logout();
      return false;
    }
    return true;
  }

  Future<void> logout() async {
    clearAccessToken();
    await _store(() async {
      await tokenStore?.clear();
    });
  }

  Future<void> _refreshAuth() =>
      _refreshing ??= _performRefresh().whenComplete(() => _refreshing = null);

  Future<void> _performRefresh() async {
    final generation = _authGeneration;
    try {
      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': _refreshToken},
      );
      if (generation != _authGeneration) {
        throw const ApiException('AUTH_REQUIRED', '请重新登录');
      }
      await saveAuthTokens(
        Map<String, dynamic>.from(_unwrap(response.data) as Map),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        if (generation == _authGeneration) await logout();
        throw const ApiException(
          'AUTH_REQUIRED',
          '登录已失效，请重新登录',
          statusCode: 401,
        );
      }
      // A temporary network failure must not discard a valid saved refresh token.
      throw const ApiException('NETWORK_ERROR', '暂时无法恢复登录，请检查网络后重试');
    }
  }

  Options get _options => Options(
    headers: {
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    },
  );

  static Dio _buildDio() => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 90),
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
        data: data is FormData ? data.clone() : data,
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
    Future<Response<dynamic>> Function() operation, {
    bool retried = false,
  }) async {
    if (!retried &&
        _refreshToken != null &&
        _expiresAt != null &&
        _expiresAt!.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
      await _refreshAuth();
    }
    final requestToken = _accessToken;
    try {
      final response = await operation();
      return _unwrap(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 &&
          !retried &&
          _refreshToken != null) {
        if (requestToken == _accessToken) await _refreshAuth();
        return _request(operation, retried: true);
      }
      final body = error.response?.data;
      final status = error.response?.statusCode;
      if (body is Map<String, dynamic> &&
          body['error_code'] != null &&
          body['message'] is String) {
        throw ApiException(
          body['error_code'].toString(),
          body['message'] as String,
          statusCode: status,
        );
      }
      final (code, message) = switch (status) {
        401 => ('AUTH_REQUIRED', '登录已失效，请重新登录后重试'),
        403 => ('ACCESS_DENIED', '当前账号暂无操作权限'),
        404 => ('HTTP_NOT_FOUND', '请求的服务接口不存在，请确认服务已更新'),
        405 => ('HTTP_METHOD_NOT_ALLOWED', '服务接口版本不兼容，请更新服务后重试'),
        413 => ('UPLOAD_TOO_LARGE', '照片过大，请选择较小的图片后重试'),
        422 => ('INVALID_REQUEST', '提交的数据不符合接口要求，请更新 App 或联系管理员'),
        429 => ('RATE_LIMITED', '操作过于频繁，请稍后重试'),
        502 || 503 => ('SERVICE_UNAVAILABLE', '服务器暂时不可用，请稍后重试'),
        504 => ('REQUEST_TIMEOUT', '服务处理超时，请稍后重试'),
        final int status when status >= 500 => (
          'SERVER_ERROR',
          '服务器处理失败，请稍后重试',
        ),
        _ => ('NETWORK_ERROR', '无法连接服务器，请检查网络或联系管理员确认服务状态'),
      };
      if (status != null) throw ApiException(code, message, statusCode: status);
      if (const {
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(error.type)) {
        throw const ApiException('REQUEST_TIMEOUT', '网络请求超时，请稍后重试');
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
  const ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => '$code: $message';
}
