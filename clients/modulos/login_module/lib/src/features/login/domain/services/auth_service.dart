import 'package:flutter/foundation.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/auth_errors.dart';
import '../model/session.dart';

/// Contrato rico de autenticação exposto pelo `login_module`.
///
/// NÃO confundir com o `AuthService` fino do `core_module` (`checkCurrentUser`,
/// gancho de boot). A implementação (`AuthServiceImpl`) satisfaz **ambos**: é
/// registrada no escopo global para os dois tipos.
///
/// Este serviço é a exceção justificada à regra "o controller fala com o
/// usecase": ele existe porque autenticação tem **estado de processo** que não
/// cabe em nenhum usecase — a sessão em memória, o refresh single-flight e o
/// `Listenable` que o guard do GoRouter escuta. O que ele *não* faz é lógica de
/// I/O ou tradução de erro: isso mora nos usecases e repositórios que ele
/// orquestra.
///
/// Cada operação devolve o seu **conjunto fechado** de erros, e não um erro
/// comum: quem chama `login` trata credenciais inválidas e rate limit; quem
/// chama `refresh` trata sessão ausente e token rejeitado. São repertórios
/// diferentes, e o compilador cobra o certo em cada caso.
abstract interface class AuthService {
  /// Autentica com e-mail/senha; em sucesso, aplica a sessão (access em memória,
  /// refresh persistido).
  Future<ReturnSuccessOrError<Session, LoginError>> login({
    required String email,
    required String password,
  });

  /// Rotaciona a sessão usando o refresh persistido (single-flight).
  Future<ReturnSuccessOrError<Session, RefreshError>> refresh();

  /// Encerra a sessão local e revoga no servidor (falha aberta no local).
  Future<ReturnSuccessOrError<Unit, LogoutError>> logout();

  /// `true` quando há sessão válida (não expirada) em memória.
  bool get isAuthenticated;

  /// A sessão atual, se houver.
  Session? get currentSession;

  /// Notifica mudanças de autenticação (login/refresh/logout) — usado como
  /// `refreshListenable` do GoRouter para reavaliar o guard.
  Listenable get authChanges;
}
