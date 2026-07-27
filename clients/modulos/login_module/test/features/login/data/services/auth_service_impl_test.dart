import 'package:api_client/api_client.dart';
import 'package:core_module/core_module.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/datasources/token_local_datasource.dart';
import 'package:login_module/src/features/login/data/repositories/login_repository.dart';
import 'package:login_module/src/features/login/data/repositories/logout_repository.dart';
import 'package:login_module/src/features/login/data/repositories/refresh_repository.dart';
import 'package:login_module/src/features/login/data/services/auth_service_impl.dart';
import 'package:login_module/src/features/login/domain/errors/auth_errors.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/parameters/login_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/logout_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/refresh_parameters.dart';
import 'package:login_module/src/features/login/domain/usecases/login_usecase.dart';
import 'package:login_module/src/features/login/domain/usecases/logout_usecase.dart';
import 'package:login_module/src/features/login/domain/usecases/refresh_token_usecase.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// SessionService em memória.
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

/// LocalStorageService em memória.
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

/// Datasource fake com contagem de chamadas e latência opcional (o atraso é o
/// que faz o teste de single-flight ter valor: sem ele, as chamadas nem se
/// sobrepõem).
final class _Ds<TData, TParams extends Parameters>
    implements Datasource<TData, TParams> {
  final TData Function()? dado;
  final Object? erro;
  final Duration atraso;
  int chamadas = 0;

  _Ds({this.dado, this.erro, this.atraso = Duration.zero});

  @override
  Future<TData> call(TParams parameters) async {
    chamadas++;
    if (atraso > Duration.zero) await Future<void>.delayed(atraso);
    if (erro != null) throw erro!;
    return dado!();
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

/// Monta o serviço sobre a cadeia REAL (repositório + usecase de produção),
/// trocando apenas o datasource — o que garante que o teste cobre também a
/// tradução de erro do `mapError`.
({
  AuthServiceImpl service,
  _FakeSessionService session,
  TokenLocalDatasource tokenStore,
  _Ds<Session, LoginParameters> loginDs,
  _Ds<Session, RefreshParameters> refreshDs,
  _Ds<Unit, LogoutParameters> logoutDs,
})
_montar({
  _Ds<Session, LoginParameters>? loginDs,
  _Ds<Session, RefreshParameters>? refreshDs,
  _Ds<Unit, LogoutParameters>? logoutDs,
  _FakeStorage? storage,
}) {
  final login = loginDs ?? _Ds<Session, LoginParameters>(dado: _session);
  final refresh = refreshDs ?? _Ds<Session, RefreshParameters>(dado: _session);
  final logout = logoutDs ?? _Ds<Unit, LogoutParameters>(dado: () => unit);
  final sessionService = _FakeSessionService();
  final tokenStore = TokenLocalDatasource(storage: storage ?? _FakeStorage());

  return (
    service: AuthServiceImpl(
      loginUsecase: LoginUsecase(
        repository: LoginRepository(datasource: login),
      ),
      refreshUsecase: RefreshTokenUsecase(
        repository: RefreshRepository(datasource: refresh),
      ),
      logoutUsecase: LogoutUsecase(
        repository: LogoutRepository(datasource: logout),
      ),
      tokenStore: tokenStore,
      session: sessionService,
    ),
    session: sessionService,
    tokenStore: tokenStore,
    loginDs: login,
    refreshDs: refresh,
    logoutDs: logout,
  );
}

void main() {
  group('login', () {
    test(
      'aplica a sessão: access em memória, só o refresh persistido',
      () async {
        final m = _montar();

        final r = await m.service.login(email: 'e@e.com', password: 'p');

        expect(r, isA<Success<Session, LoginError>>());
        expect(m.service.isAuthenticated, isTrue);
        expect(m.service.currentSession?.tenantId, 'tenant-1');
        expect(
          m.session.token,
          'access',
          reason: 'access vai para o interceptor',
        );
        expect(await m.tokenStore.readRefresh(), 'refresh-novo');
      },
    );

    test('notifica os ouvintes (guard do GoRouter reavalia)', () async {
      final m = _montar();
      var notificacoes = 0;
      m.service.authChanges.addListener(() => notificacoes++);

      await m.service.login(email: 'e@e.com', password: 'p');

      expect(notificacoes, 1);
    });

    test('falha não aplica sessão nem persiste nada', () async {
      final m = _montar(
        loginDs: _Ds<Session, LoginParameters>(
          erro: GrpcError.unauthenticated('errors.auth'),
        ),
      );

      final r = await m.service.login(email: 'e@e.com', password: 'errada');

      expect((r as Failure).error, isA<CredenciaisInvalidas>());
      expect(m.service.isAuthenticated, isFalse);
      expect(m.session.token, isNull);
      expect(await m.tokenStore.readRefresh(), isNull);
    });

    test('sessão expirada não conta como autenticada', () async {
      final m = _montar(
        loginDs: _Ds<Session, LoginParameters>(
          dado: () => _session(ttl: const Duration(seconds: -1)),
        ),
      );

      await m.service.login(email: 'e@e.com', password: 'p');

      expect(m.service.currentSession, isNotNull);
      expect(m.service.isAuthenticated, isFalse);
    });
  });

  group('refresh', () {
    test('single-flight: N chamadas concorrentes → 1 RPC', () async {
      final storage = _FakeStorage();
      final m = _montar(
        storage: storage,
        refreshDs: _Ds<Session, RefreshParameters>(
          dado: _session,
          atraso: const Duration(milliseconds: 20),
        ),
      );
      await m.tokenStore.writeRefresh('refresh-antigo');

      final resultados = await Future.wait([
        m.service.refresh(),
        m.service.refresh(),
        m.service.refresh(),
        m.service.refresh(),
        m.service.refresh(),
      ]);

      expect(m.refreshDs.chamadas, 1, reason: 'compartilharam a mesma Future');
      expect(resultados.every((r) => r is Success), isTrue);
    });

    test('nova chamada depois de concluída dispara outro RPC', () async {
      final m = _montar();
      await m.tokenStore.writeRefresh('refresh-antigo');

      await m.service.refresh();
      await m.service.refresh();

      expect(m.refreshDs.chamadas, 2, reason: 'a Future em voo foi liberada');
    });

    test(
      'sem token persistido devolve SemSessaoPersistida sem tocar a rede',
      () async {
        final m = _montar();

        final r = await m.service.refresh();

        expect((r as Failure).error, isA<SemSessaoPersistida>());
        expect(m.refreshDs.chamadas, 0);
        expect(m.service.isAuthenticated, isFalse);
      },
    );

    test('token vazio conta como ausente', () async {
      final m = _montar();
      await m.tokenStore.writeRefresh('');

      final r = await m.service.refresh();

      expect((r as Failure).error, isA<SemSessaoPersistida>());
      expect(m.refreshDs.chamadas, 0);
    });

    test('rejeição do servidor derruba a sessão local', () async {
      final m = _montar(
        refreshDs: _Ds<Session, RefreshParameters>(
          erro: GrpcError.unauthenticated('errors.auth'),
        ),
      );
      await m.tokenStore.writeRefresh('reutilizado');
      // Estado de partida: autenticado.
      await m.service.login(email: 'e@e.com', password: 'p');

      final r = await m.service.refresh();

      expect((r as Failure).error, isA<RefreshRejeitado>());
      expect(m.service.isAuthenticated, isFalse);
      expect(m.session.token, isNull);
      expect(await m.tokenStore.readRefresh(), isNull);
    });

    test('servidor indisponível NÃO derruba a sessão em memória', () async {
      // Deslogar por instabilidade de rede seria hostil: o access token em
      // memória pode ainda estar válido por vários minutos.
      final m = _montar(
        refreshDs: _Ds<Session, RefreshParameters>(
          erro: GrpcError.unavailable('offline'),
        ),
      );
      await m.service.login(email: 'e@e.com', password: 'p');

      final r = await m.service.refresh();

      expect((r as Failure).error, isA<RefreshIndisponivel>());
      expect(m.service.isAuthenticated, isTrue);
      expect(m.session.token, 'access');
      expect(await m.tokenStore.readRefresh(), 'refresh-novo');
    });

    test('sucesso rotaciona o refresh persistido', () async {
      final m = _montar();
      await m.tokenStore.writeRefresh('refresh-antigo');

      await m.service.refresh();

      expect(await m.tokenStore.readRefresh(), 'refresh-novo');
    });
  });

  group('checkCurrentUser (gancho de boot)', () {
    test('sem sessão persistida: fica deslogado, sem lançar', () async {
      final m = _montar();

      await m.service.checkCurrentUser();

      expect(m.service.isAuthenticated, isFalse);
    });

    test('com refresh válido: auto-login silencioso', () async {
      final m = _montar();
      await m.tokenStore.writeRefresh('refresh-antigo');

      await m.service.checkCurrentUser();

      expect(m.service.isAuthenticated, isTrue);
      expect(m.session.token, 'access');
    });

    test('falha no boot limpa qualquer resíduo persistido', () async {
      final m = _montar(
        refreshDs: _Ds<Session, RefreshParameters>(
          erro: GrpcError.unavailable('offline'),
        ),
      );
      await m.tokenStore.writeRefresh('resto-de-sessao');

      await m.service.checkCurrentUser();

      expect(m.service.isAuthenticated, isFalse);
      expect(await m.tokenStore.readRefresh(), isNull);
    });
  });

  group('logout', () {
    test('limpa memória e storage', () async {
      final m = _montar();
      await m.service.login(email: 'e@e.com', password: 'p');
      expect(m.service.isAuthenticated, isTrue);

      final r = await m.service.logout();

      expect(r, isA<Success<Unit, LogoutError>>());
      expect(m.service.isAuthenticated, isFalse);
      expect(m.session.token, isNull);
      expect(await m.tokenStore.readRefresh(), isNull);
    });

    test('envia o refresh persistido para revogar a família', () async {
      final m = _montar();
      await m.service.login(email: 'e@e.com', password: 'p');

      await m.service.logout();

      expect(m.logoutDs.chamadas, 1);
    });

    test(
      'falha aberta: servidor indisponível ainda encerra a sessão local',
      () async {
        final m = _montar(
          logoutDs: _Ds<Unit, LogoutParameters>(
            erro: GrpcError.unavailable('offline'),
          ),
        );
        await m.service.login(email: 'e@e.com', password: 'p');

        final r = await m.service.logout();

        expect((r as Failure).error, isA<LogoutIndisponivel>());
        expect(
          m.service.isAuthenticated,
          isFalse,
          reason: 'o usuário pediu para sair; prendê-lo na sessão seria pior',
        );
        expect(await m.tokenStore.readRefresh(), isNull);
      },
    );

    test('notifica os ouvintes ao encerrar', () async {
      final m = _montar();
      await m.service.login(email: 'e@e.com', password: 'p');
      var notificacoes = 0;
      m.service.authChanges.addListener(() => notificacoes++);

      await m.service.logout();

      expect(notificacoes, 1);
    });
  });

  group('marcadores transversais', () {
    test(
      'erro de rede do refresh é NetworkFailure, não UnauthorizedFailure',
      () async {
        final m = _montar(
          refreshDs: _Ds<Session, RefreshParameters>(
            erro: GrpcError.unavailable('offline'),
          ),
        );
        await m.tokenStore.writeRefresh('rt');

        final erro = ((await m.service.refresh()) as Failure).error;

        expect(erro, isA<NetworkFailure>());
        expect(erro, isNot(isA<UnauthorizedFailure>()));
      },
    );

    test(
      'sessão ausente é UnauthorizedFailure (o guard manda para o login)',
      () async {
        final m = _montar();

        final erro = ((await m.service.refresh()) as Failure).error;

        expect(erro, isA<UnauthorizedFailure>());
      },
    );
  });
}
