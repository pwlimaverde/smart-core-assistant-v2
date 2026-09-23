import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/usuarios_errors.dart';
import '../model/migracao_de_escopos.dart';
import '../model/usuario_global.dart';
import '../parameters/usuarios_parameters.dart';

/// Casos de uso da feature `usuarios` (D7).
///
/// A regra de quem pode o quê vive no servidor — inclusive a recusa a bloquear
/// o próprio acesso, que não pode depender do cliente. O que a base agrega aqui
/// é o `onUnexpected`.
void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'admin_module.usuarios',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lista usuários de todos os tenants.
final class ListarUsuariosUsecase
    extends
        UsecaseBaseCallData<
          List<UsuarioGlobal>,
          List<UsuarioGlobal>,
          ListarUsuariosParameters,
          UsuariosError
        > {
  const ListarUsuariosUsecase({required super.repository});

  /// Ordena bloqueados primeiro, depois por nome.
  ///
  /// Quem abre esta tela quase sempre veio investigar um acesso que não
  /// funciona; deixar os bloqueados no topo poupa a busca justamente no caso
  /// mais comum. A ordenação é da apresentação, não do servidor — que já
  /// devolve por data de cadastro para paginar de forma estável.
  @override
  ProcessData<
    List<UsuarioGlobal>,
    List<UsuarioGlobal>,
    ListarUsuariosParameters,
    UsuariosError
  >
  get process =>
      (data, _) => Success(
        List.of(data)..sort((a, b) {
          if (a.ativo != b.ativo) return a.ativo ? 1 : -1;
          return a.exibicao.toLowerCase().compareTo(b.exibicao.toLowerCase());
        }),
      );

  @override
  UsuariosError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listarUsuarios', exception, stackTrace);
    return const UsuariosInesperado();
  }
}

/// Bloqueia/desbloqueia o acesso de um usuário.
final class DefinirUsuarioAtivoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DefinirUsuarioAtivoParameters,
          UsuariosError
        > {
  const DefinirUsuarioAtivoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DefinirUsuarioAtivoParameters, UsuariosError>
  get process =>
      (data, _) => Success(data);

  @override
  UsuariosError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('definirUsuarioAtivo', exception, stackTrace);
    return const UsuariosInesperado();
  }
}

/// P18 — migra (ou só conta) os escopos implícitos. A contagem vem ordenada
/// pelo maior grupo: é o que o superusuário quer ver primeiro.
final class MigrarEscoposUsecase
    extends
        UsecaseBaseCallData<
          ResultadoDaMigracao,
          ResultadoDaMigracao,
          MigrarEscoposParameters,
          UsuariosError
        > {
  const MigrarEscoposUsecase({required super.repository});

  @override
  ProcessData<
    ResultadoDaMigracao,
    ResultadoDaMigracao,
    MigrarEscoposParameters,
    UsuariosError
  >
  get process =>
      (data, _) => Success(
        ResultadoDaMigracao(
          contagens: List.of(data.contagens)
            ..sort((a, b) => b.quantidade.compareTo(a.quantidade)),
          total: data.total,
          migrados: data.migrados,
          pulados: data.pulados,
          simulacao: data.simulacao,
        ),
      );

  @override
  UsuariosError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('migrarEscopos', exception, stackTrace);
    return const UsuariosInesperado();
  }
}
