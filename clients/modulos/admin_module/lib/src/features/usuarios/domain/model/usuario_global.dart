import 'package:meta/meta.dart';

/// Um usuário na visão do superusuário (D7).
///
/// A v1 tinha esta lista no admin do Django; a v2 só tinha `ListTenantUsers`,
/// que resolve o tenant a partir de quem chama e nunca enxerga além do próprio.
/// Sem ela, "o cliente diz que não consegue entrar" não tem por onde começar.
@immutable
class UsuarioGlobal {
  final int id;
  final String username;
  final String email;
  final String nome;

  /// `false` = acesso bloqueado. O login recusa.
  final bool ativo;

  final bool superusuario;

  /// `null` quando nunca entrou — o servidor manda `0` e a conversão trata.
  final DateTime? ultimoLogin;

  final DateTime cadastradoEm;

  /// Tenant de que este usuário é **dono**, se for de algum.
  final String tenantDono;

  /// Tenant em que este usuário é **funcionário**, se for de algum.
  final String tenantMembro;

  /// Papel como funcionário, quando houver.
  final String papel;

  const UsuarioGlobal({
    required this.id,
    required this.username,
    required this.email,
    required this.nome,
    required this.ativo,
    required this.superusuario,
    required this.ultimoLogin,
    required this.cadastradoEm,
    required this.tenantDono,
    required this.tenantMembro,
    required this.papel,
  });

  /// Como apresentar a pessoa: o nome quando existe, o username quando não.
  ///
  /// `first_name`/`last_name` são opcionais no cadastro, e uma linha em branco
  /// numa lista de suporte é pior que um username feio.
  String get exibicao => nome.trim().isEmpty ? username : nome.trim();

  /// A que tenant este usuário pertence, para a coluna da tabela.
  ///
  /// Dono tem precedência sobre funcionário: é o vínculo mais forte, e quem
  /// abre esta tela quer saber de quem é a conta antes de saber o cargo.
  /// Vazio nos dois = superusuário do sistema, que não pertence a tenant algum.
  String get vinculo {
    if (tenantDono.isNotEmpty) return tenantDono;
    if (tenantMembro.isNotEmpty) return tenantMembro;
    return '';
  }
}
