import 'package:core_module/core_module.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/auth_errors.dart';
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
///
/// Os usecases são **injetados**, não construídos aqui: antes, cada chamada
/// fazia `LoginUsecase(datasource: _loginDs)`, o que amarrava o serviço à
/// construção da cadeia inteira e tornava impossível testá-lo contra um usecase
/// falso sem também montar datasource e repositório.
final class AuthServiceImpl implements AuthService, core.AuthService {
  final LoginUsecase _loginUsecase;
  final RefreshTokenUsecase _refreshUsecase;
  final LogoutUsecase _logoutUsecase;
  final TokenLocalDatasource _tokenStore;
  final core.SessionService _session;

  Session? _current;
  Future<ReturnSuccessOrError<Session, RefreshError>>? _refreshInFlight;
  final ValueNotifier<int> _authChanges = ValueNotifier<int>(0);

  /// Dependências recebidas como private named parameters (Dart 3.12): o
  /// chamador usa os nomes públicos (`loginUsecase`, `tokenStore`, …) e os
  /// campos permanecem privados.
  AuthServiceImpl({
    required this._loginUsecase,
    required this._refreshUsecase,
    required this._logoutUsecase,
    required this._tokenStore,
    required this._session,
  });

  @override
  bool get isAuthenticated => _current != null && !_current!.isExpired;

  @override
  Session? get currentSession => _current;

  @override
  Listenable get authChanges => _authChanges;

  @override
  Future<ReturnSuccessOrError<Session, LoginError>> login({
    required String email,
    required String password,
  }) async {
    final result = await _loginUsecase(
      LoginParameters(email: email, password: password),
    );
    if (result case Success(:final value)) await _aplicarSessao(value);
    return result;
  }

  /// Refresh com single-flight: chamadas concorrentes compartilham a MESMA
  /// Future. Sem isso, várias telas percebendo o 401 ao mesmo tempo rotacionariam
  /// o refresh em paralelo — e a detecção de reuso do servidor invalidaria a
  /// família inteira, deslogando o usuário por causa da concorrência.
  @override
  Future<ReturnSuccessOrError<Session, RefreshError>> refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(
      () => _refreshInFlight = null,
    );
  }

  Future<ReturnSuccessOrError<Session, RefreshError>> _doRefresh() async {
    final stored = await _tokenStore.readRefresh();
    if (stored == null || stored.isEmpty) {
      // Estado normal do primeiro boot: não houve I/O, não há o que limpar.
      return const Failure(SemSessaoPersistida());
    }
    final result = await _refreshUsecase(
      RefreshParameters(refreshToken: stored),
    );
    switch (result) {
      case Success(:final value):
        await _aplicarSessao(value);
      case Failure(:final error):
        // Só derruba a sessão quando o servidor REJEITOU o token. Indisponível
        // ou inesperado pode ser instabilidade de rede, e o access em memória
        // talvez ainda esteja válido — deslogar aí seria hostil.
        if (error is RefreshRejeitado) await _limparSessao();
    }
    return result;
  }

  /// Gancho de boot (auto-login silencioso): tenta refresh com o token
  /// persistido. Falha é esperada quando não há sessão — não propaga, só fica
  /// deslogado.
  @override
  Future<void> checkCurrentUser() async {
    final result = await refresh();
    if (result is Failure) await _limparSessao();
  }

  @override
  Future<ReturnSuccessOrError<Unit, LogoutError>> logout() async {
    final stored = await _tokenStore.readRefresh();
    final result = await _logoutUsecase(LogoutParameters(refreshToken: stored));
    // Falha aberta: limpa o estado local mesmo se a revogação no servidor
    // falhar. O contrário deixaria o usuário preso numa sessão que ele pediu
    // para encerrar.
    await _limparSessao();
    return result;
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
