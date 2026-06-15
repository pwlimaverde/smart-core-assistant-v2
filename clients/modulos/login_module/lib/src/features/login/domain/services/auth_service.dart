import 'package:flutter/foundation.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/session.dart';

/// Contrato rico de autenticação exposto pelo `login_module`.
///
/// NÃO confundir com o `AuthService` fino do `core_module` (`checkCurrentUser`,
/// gancho de boot). A implementação (`AuthServiceImpl`) satisfaz **ambos**: é
/// registrada no escopo global para os dois tipos.
abstract interface class AuthService {
  /// Autentica com e-mail/senha; em sucesso, aplica a sessão (access em memória,
  /// refresh persistido).
  Future<ReturnSuccessOrError<Session>> login({
    required String email,
    required String password,
  });

  /// Rotaciona a sessão usando o refresh persistido (single-flight).
  Future<ReturnSuccessOrError<Session>> refresh();

  /// Encerra a sessão local e revoga no servidor (falha aberta no local).
  Future<ReturnSuccessOrError<Unit>> logout();

  /// `true` quando há sessão válida (não expirada) em memória.
  bool get isAuthenticated;

  /// A sessão atual, se houver.
  Session? get currentSession;

  /// Notifica mudanças de autenticação (login/refresh/logout) — usado como
  /// `refreshListenable` do GoRouter para reavaliar o guard.
  Listenable get authChanges;
}
