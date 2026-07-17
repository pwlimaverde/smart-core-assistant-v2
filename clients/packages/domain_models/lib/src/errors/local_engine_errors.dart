import 'package:meta/meta.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Falha do motor local (FFI/`local_engine`): índice SQLite, fila offline, cache
/// de mídia ou sincronização. Mapeada na fronteira do `LocalEngineFfiDataSource`
/// a partir das falhas do Rust (`LocalEngineError`/`anyhow`) — o `local_engine`
/// só roda no desktop, então este erro nunca aparece no target Web.
@immutable
final class ErrorLocalEngine implements AppError {
  @override
  final String message;
  const ErrorLocalEngine({this.message = 'Falha no motor local.'});

  @override
  ErrorLocalEngine copyWith({String? message}) =>
      ErrorLocalEngine(message: message ?? this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorLocalEngine && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => '$runtimeType - $message';
}
