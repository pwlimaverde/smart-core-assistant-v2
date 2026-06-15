import 'package:meta/meta.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros de domínio tipados, compartilhados entre as camadas (data → presentation).
///
/// São [AppError] imutáveis com igualdade por valor e `copyWith` polimórfico
/// (o tipo concreto é preservado ao enriquecer a mensagem). A mensagem padrão é
/// amigável em pt-br; o [ErrorMessageMapper] (presentation) resolve a exibição.

/// Falha de autenticação genérica (credenciais inválidas, emissão de token, etc.).
@immutable
final class ErrorAuth implements AppError {
  @override
  final String message;
  const ErrorAuth({this.message = 'Falha ao autenticar.'});

  @override
  ErrorAuth copyWith({String? message}) =>
      ErrorAuth(message: message ?? this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ErrorAuth && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => '$runtimeType - $message';
}

/// Sessão ausente/expirada ou acesso não autorizado (`unauthenticated`).
@immutable
final class ErrorUnauthorized implements AppError {
  @override
  final String message;
  const ErrorUnauthorized({this.message = 'Sessão expirada. Entre novamente.'});

  @override
  ErrorUnauthorized copyWith({String? message}) =>
      ErrorUnauthorized(message: message ?? this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorUnauthorized && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => '$runtimeType - $message';
}

/// Falha de rede/transporte (servidor indisponível, sem conexão).
@immutable
final class ErrorNetwork implements AppError {
  @override
  final String message;
  const ErrorNetwork({this.message = 'Servidor indisponível. Tente novamente.'});

  @override
  ErrorNetwork copyWith({String? message}) =>
      ErrorNetwork(message: message ?? this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorNetwork && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => '$runtimeType - $message';
}

/// Dados de entrada inválidos (`invalid_argument`).
@immutable
final class ErrorValidation implements AppError {
  @override
  final String message;
  const ErrorValidation({this.message = 'Dados inválidos.'});

  @override
  ErrorValidation copyWith({String? message}) =>
      ErrorValidation(message: message ?? this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorValidation && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => '$runtimeType - $message';
}
