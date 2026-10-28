import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryTokens implements TokenStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> tokens) async {
    value = {...tokens};
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  Map<String, dynamic> tokens({int expires = 3600}) => {
    'access_token': 'access-1',
    'refresh_token': 'refresh-1',
    'expires_in': expires,
  };
  ApiClient client(
    MemoryTokens store,
    void Function(RequestOptions, RequestInterceptorHandler) handler,
  ) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: handler));
    return ApiClient(dio: dio, tokenStore: store);
  }

  void ok(RequestOptions r, RequestInterceptorHandler h, Object data) =>
      h.resolve(
        Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': 0, 'data': data},
        ),
      );
  void fail(RequestOptions r, RequestInterceptorHandler h, int status) =>
      h.reject(
        DioException(
          requestOptions: r,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: r,
            statusCode: status,
            data: {'code': 1},
          ),
        ),
      );

  test('restart restores tokens without another login and logout erases only session', () async {
    final store = MemoryTokens();
    await client(store, (_, _) {}).saveAuthTokens(tokens());
    final reopened = client(store, (r, h) {
      expect(r.headers['Authorization'], 'Bearer access-1');
      ok(r, h, {'name': 'Fan'});
    });
    expect(await reopened.restoreAuthTokens(), isTrue);
    await reopened.getData('/me/profile');
    await reopened.logout();
    expect(store.value, isNull);
    expect(await client(store, (_, _) {}).restoreAuthTokens(), isFalse);
  });

  test('expired access token renews once for concurrent requests', () async {
    final store = MemoryTokens();
    var refreshes = 0;
    final c = client(store, (r, h) async {
      if (r.path == '/auth/refresh') {
        refreshes++;
        expect(r.data['refresh_token'], 'refresh-1');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        ok(r, h, {...tokens(), 'access_token': 'access-2'});
      } else {
        expect(r.headers['Authorization'], 'Bearer access-2');
        ok(r, h, {});
      }
    });
    await c.saveAuthTokens(tokens(expires: -1));
    await Future.wait([
      c.getData('/me/profile'),
      c.getData('/me/name-preferences'),
      c.getData('/catalog/profiles/groups/test'),
    ]);
    expect(refreshes, 1);
    expect(store.value!['access_token'], 'access-2');
  });

  test(
    'malformed saved credentials are discarded without a type error',
    () async {
      final store = MemoryTokens()
        ..value = {
          'access_token': 42,
          'refresh_token': 'refresh-1',
          'expires_at': '2026-10-14T00:00:00Z',
        };
      expect(await client(store, (_, _) {}).restoreAuthTokens(), isFalse);
      expect(store.value, isNull);
    },
  );

  test(
    'network failure preserves credentials but rejected refresh clears them',
    () async {
      final store = MemoryTokens();
      final c = client(
        store,
        (r, h) => h.reject(
          DioException(
            requestOptions: r,
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );
      await c.saveAuthTokens(tokens(expires: -1));
      await expectLater(c.getData('/me/profile'), throwsA(isA<ApiException>()));
      expect(store.value!['refresh_token'], 'refresh-1');
      final rejected = client(store, (r, h) => fail(r, h, 401));
      await rejected.restoreAuthTokens();
      await expectLater(
        rejected.getData('/me/profile'),
        throwsA(isA<ApiException>()),
      );
      expect(store.value, isNull);
    },
  );

  test('401 retries exactly once with renewed authorization', () async {
    final store = MemoryTokens();
    var requests = 0;
    final c = client(store, (r, h) {
      if (r.path == '/auth/refresh') {
        ok(r, h, {...tokens(), 'access_token': 'access-2'});
      } else if (++requests == 1) {
        fail(r, h, 401);
      } else {
        expect(r.headers['Authorization'], 'Bearer access-2');
        ok(r, h, {});
      }
    });
    await c.saveAuthTokens(tokens());
    await c.getData('/me/profile');
    expect(requests, 2);
  });

  test(
    'catalog timeout wrapper refreshes authorization on a 401 retry',
    () async {
      final store = MemoryTokens();
      var requests = 0;
      final c = client(store, (r, h) {
        if (r.path == '/auth/refresh') {
          ok(r, h, {...tokens(), 'access_token': 'access-2'});
        } else if (++requests == 1) {
          fail(r, h, 401);
        } else {
          expect(r.headers['Authorization'], 'Bearer access-2');
          ok(r, h, {'fields': []});
        }
      });
      await c.saveAuthTokens(tokens());
      await c.getData('/catalog/profiles/groups/test');
      expect(requests, 2);
    },
  );

  test(
    'public support bypasses stale auth and never sends access token',
    () async {
      final store = MemoryTokens();
      final c = client(store, (r, h) {
        expect(r.path, '/auth/support-entry');
        expect(r.headers['Authorization'], isNull);
        ok(r, h, {'enabled': false});
      });
      await c.saveAuthTokens(tokens(expires: -1));
      await c.getData('/auth/support-entry', authenticated: false);
      expect(store.value, isNotNull);
    },
  );

  test('banned error preserves public help details during refresh', () async {
    final store = MemoryTokens();
    final c = client(
      store,
      (r, h) => h.reject(
        DioException(
          requestOptions: r,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: r,
            statusCode: 403,
            data: {
              'code': 1,
              'error_code': 'ACCOUNT_BANNED',
              'message': '账号已被封禁',
              'data': {
                'public_message': '请联系支持',
                'request_id': 'appeal-123',
                'support_entry_id': 'login-support',
              },
            },
          ),
        ),
      ),
    );
    ApiException? observed;
    c.onAccountBanned = (error) => observed = error;
    await c.saveAuthTokens(tokens(expires: -1));
    await expectLater(
      c.getData('/me/profile'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'ACCOUNT_BANNED'),
      ),
    );
    expect(observed?.details['request_id'], 'appeal-123');
    expect(observed?.details['public_message'], '请联系支持');
    expect(store.value, isNull);
  });

  test(
    'explicitly keyed auth mutation retries loss with same key and payload',
    () async {
      var calls = 0;
      final c = client(MemoryTokens(), (r, h) {
        expect(r.headers['Idempotency-Key'], 'stable-key');
        expect(r.headers['Authorization'], isNull);
        expect(r.data, {'phone': '13812345678', 'purpose': 'login'});
        if (++calls == 1) {
          h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.receiveTimeout,
            ),
          );
        } else {
          ok(r, h, {'challenge_id': 'one'});
        }
      });
      final value = await c.postData(
        '/auth/sms/challenges',
        authenticated: false,
        idempotencyKey: 'stable-key',
        data: {'phone': '13812345678', 'purpose': 'login'},
      );
      expect(calls, 2);
      expect(value['challenge_id'], 'one');
    },
  );

  test('logout during refresh cannot resurrect the old account', () async {
    final store = MemoryTokens();
    final entered = Completer<void>();
    final release = Completer<void>();
    final c = client(store, (r, h) async {
      entered.complete();
      await release.future;
      ok(r, h, tokens());
    });
    await c.saveAuthTokens(tokens(expires: -1));
    final request = c.getData('/me/profile');
    final assertion = expectLater(request, throwsA(isA<ApiException>()));
    await entered.future;
    await c.logout();
    release.complete();
    await assertion;
    expect(store.value, isNull);
  });
}
