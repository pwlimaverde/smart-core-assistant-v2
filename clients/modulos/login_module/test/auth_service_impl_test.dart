import 'package:core_module/core_module.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/datasources/token_local_datasource.dart';
import 'package:login_module/src/features/login/data/services/auth_service_impl.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// SessionService em memória para teste.
class _FakeSessionService implements SessionService {
  String? _t;
  String? _ten;
  @override
  String? get token => _t;
  @override
  String? get tenantId => _ten;
  @override
  void setSession({required String token, String? tenantId}) {
    _t = token;
    _ten = tenantId;
  }

  @override
  void clearSession() {
    _t = null;
    _ten = null;
  }
}

/// LocalStorageService em memória para teste.
class _FakeStorage implements LocalStorageService {
  final Map<String, String> _m = {};
  @override
  Future<void> init() async {}
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  String? read(String key) => _m[key];
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

class _FakeSessionDatasource implements Datasource<Session> {
  final Session session;
  int calls = 0;
  _FakeSessionDatasource({required this.session});
  @override
  Future<Session> call(covariant ParametersReturnResult p) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return session;
  }
}

class _FakeUnitDatasource implements Datasource<Unit> {
  int calls = 0;
  @override
  Future<Unit> call(covariant ParametersReturnResult p) async {
    calls++;
    return unit;
  }
}

Session _session({Duration ttl = const Duration(minutes: 15)}) => Session(
      accessToken: 'access',
      refreshToken: 'refresh-novo',
      expiresAt: DateTime.now().add(ttl),
      tenantId: 'tenant-1',
      scopes: const ['atendimentos:read'],
      isSuperuser: false,
    );

AuthServiceImpl _build({
  _FakeSessionDatasource? loginDs,
  _FakeSessionDatasource? refreshDs,
  _FakeUnitDatasource? logoutDs,
  required TokenLocalDatasource tokenStore,
  required SessionService session,
}) =>
    AuthServiceImpl(
      loginDatasource: loginDs ?? _FakeSessionDatasource(session: _session()),
      refreshDatasource:
          refreshDs ?? _FakeSessionDatasource(session: _session()),
      logoutDatasource: logoutDs ?? _FakeUnitDatasource(),
      tokenStore: tokenStore,
      session: session,
    );

void main() {
  test('login aplica a sessão: access em memória + refresh persistido', () async {
    final storage = _FakeStorage();
    final session = _FakeSessionService();
    final tokenStore = TokenLocalDatasource(storage: storage);
    final impl = _build(tokenStore: tokenStore, session: session);

    final r = await impl.login(email: 'e@e.com', password: 'p');

    expect(r, isA<SuccessReturn<Session>>());
    expect(impl.isAuthenticated, isTrue);
    expect(session.token, 'access'); // access em memória (interceptor)
    expect(await tokenStore.readRefresh(), 'refresh-novo'); // só refresh persiste
  });

  test('refresh single-flight: N chamadas concorrentes → 1 RPC', () async {
    final storage = _FakeStorage();
    final tokenStore = TokenLocalDatasource(storage: storage);
    await tokenStore.writeRefresh('refresh-antigo');
    final refreshDs = _FakeSessionDatasource(session: _session());
    final impl = _build(
      refreshDs: refreshDs,
      tokenStore: tokenStore,
      session: _FakeSessionService(),
    );

    final resultados = await Future.wait([
      impl.refresh(),
      impl.refresh(),
      impl.refresh(),
      impl.refresh(),
      impl.refresh(),
    ]);

    expect(refreshDs.calls, 1); // single-flight compartilhou a Future
    expect(resultados.every((r) => r is SuccessReturn<Session>), isTrue);
  });

  test('refresh sem token persistido → ErrorUnauthorized e sessão limpa',
      () async {
    final impl = _build(
      tokenStore: TokenLocalDatasource(storage: _FakeStorage()),
      session: _FakeSessionService(),
    );

    final r = await impl.refresh();

    expect(r, isA<ErrorReturn<Session>>());
    expect((r as ErrorReturn<Session>).result, isA<ErrorUnauthorized>());
    expect(impl.isAuthenticated, isFalse);
  });

  test('checkCurrentUser: auto-login silencioso falha sem sessão (não lança)',
      () async {
    final impl = _build(
      tokenStore: TokenLocalDatasource(storage: _FakeStorage()),
      session: _FakeSessionService(),
    );
    await impl.checkCurrentUser();
    expect(impl.isAuthenticated, isFalse);
  });

  test('logout limpa memória e storage (falha aberta)', () async {
    final storage = _FakeStorage();
    final session = _FakeSessionService();
    final tokenStore = TokenLocalDatasource(storage: storage);
    final impl = _build(tokenStore: tokenStore, session: session);

    await impl.login(email: 'e@e.com', password: 'p');
    expect(impl.isAuthenticated, isTrue);

    final r = await impl.logout();
    expect(r, isA<SuccessReturn<Unit>>());
    expect(impl.isAuthenticated, isFalse);
    expect(session.token, isNull);
    expect(await tokenStore.readRefresh(), isNull);
  });
}
