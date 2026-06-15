import 'package:core_module/core_module.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/session.dart';
import '../../domain/parameters/login_parameters.dart';
import '../../domain/parameters/logout_parameters.dart';
import '../../domain/parameters/refresh_parameters.dart';
import '../../domain/services/auth_service.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/refresh_token_usecase.dart';
import '../datasources/token_local_datasource.dart';

/// Implementação rica de [AuthService] que também satisfaz o gancho de boot
/// `core.AuthService.checkCurrentUser`.
///
/// Orquestra: sessão em memória, persistência do refresh (secure storage),
/// população do `SessionService` (access em memória, para o interceptor) e o
/// **refresh single-flight** (chamadas concorrentes compartilham uma Future).
final class AuthServiceImpl implements AuthService, core.AuthService {
  final Datasource<Session> _loginDs;
  final Datasource<Session> _refreshDs;
  final Datasource<Unit> _logoutDs;
  final TokenLocalDatasource _tokenStore;
  final core.SessionService _session;

  Session? _current;
  Future<ReturnSuccessOrError<Session>>? _refreshInFlight;
  final ValueNotifier<int> _authChanges = ValueNotifier<int>(0);

  AuthServiceImpl({
    required Datasource<Session> loginDatasource,
    required Datasource<Session> refreshDatasource,
    required Datasource<Unit> logoutDatasource,
    required TokenLocalDatasource tokenStore,
    required core.SessionService session,
  })  : _loginDs = loginDatasource,
        _refreshDs = refreshDatasource,
        _logoutDs = logoutDatasource,
        _tokenStore = tokenStore, // ignore: prefer_initializing_formals
        _session = session; // ignore: prefer_initializing_formals

  @override
  bool get isAuthenticated => _current != null && !_current!.isExpired;

  @override
  Session? get currentSession => _current;

  @override
  Listenable get authChanges => _authChanges;

  @override
  Future<ReturnSuccessOrError<Session>> login({
    required String email,
    required String password,
  }) async {
    final result = await LoginUsecase(datasource: _loginDs)
        .call(LoginParameters(email: email, password: password));
    switch (result) {
      case SuccessReturn<Session>():
        await _aplicarSessao(result.result);
      case ErrorReturn<Session>():
        break;
    }
    return result;
  }

  /// Refresh com single-flight: chamadas concorrentes compartilham a MESMA Future.
  @override
  Future<ReturnSuccessOrError<Session>> refresh() {
    return _refreshInFlight ??=
        _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<ReturnSuccessOrError<Session>> _doRefresh() async {
    final stored = await _tokenStore.readRefresh();
    if (stored == null || stored.isEmpty) {
      return const ErrorReturn(
        error: ErrorUnauthorized(message: 'Sem sessão persistida.'),
      );
    }
    final result = await RefreshTokenUsecase(datasource: _refreshDs)
        .call(RefreshParameters(refreshToken: stored));
    switch (result) {
      case SuccessReturn<Session>():
        await _aplicarSessao(result.result);
      case ErrorReturn<Session>():
        await _limparSessao(); // refresh inválido → logout local
    }
    return result;
  }

  /// Gancho de boot (auto-login silencioso): tenta refresh com o token persistido.
  /// `ErrorReturn` é esperado quando não há sessão — não propaga, só fica deslogado.
  @override
  Future<void> checkCurrentUser() async {
    final r = await refresh();
    if (r is ErrorReturn) await _limparSessao();
  }

  @override
  Future<ReturnSuccessOrError<Unit>> logout() async {
    final refresh = await _tokenStore.readRefresh();
    final result = await LogoutUsecase(datasource: _logoutDs)
        .call(LogoutParameters(refreshToken: refresh));
    // Falha aberta: limpa o estado local mesmo se a revogação no servidor falhar.
    await _limparSessao();
    return switch (result) {
      SuccessReturn<Unit>() => const SuccessReturn(success: unit),
      ErrorReturn<Unit>() => result,
    };
  }

  Future<void> _aplicarSessao(Session s) async {
    _current = s;
    _session.setSession(token: s.accessToken, tenantId: s.tenantId);
    await _tokenStore.writeRefresh(s.refreshToken);
    _notificar();
  }

  Future<void> _limparSessao() async {
    _current = null;
    _session.clearSession();
    await _tokenStore.deleteRefresh();
    _notificar();
  }

  void _notificar() => _authChanges.value++;
}
