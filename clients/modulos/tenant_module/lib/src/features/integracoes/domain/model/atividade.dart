import 'package:meta/meta.dart';

/// Uma linha da trilha do tenant, na aba "Atividade" (B3).
///
/// Não carrega a mensagem do evento, e é de propósito: alguns eventos guardam
/// nome ou e-mail na mensagem, e esta tela não mostra dado pessoal. O servidor
/// nem a manda — não é a tela que decide o que esconder.
@immutable
class Atividade {
  final DateTime quando;

  /// Código do evento na trilha (`contato_cadastrado`).
  final String evento;

  /// `true` quando quem agiu foi um aplicativo conectado.
  final bool porAgente;

  /// Nome do aplicativo. **Texto de terceiro** — vem do documento que o próprio
  /// cliente publica.
  final String aplicativo;

  /// Operação chamada pelo agente (`SendOutboundMessage`), quando houver.
  final String operacao;

  /// Quem agiu no painel, ou quem autorizou o agente.
  final String quem;

  final String grantId;

  const Atividade({
    required this.quando,
    required this.evento,
    required this.porAgente,
    required this.aplicativo,
    required this.operacao,
    required this.quem,
    required this.grantId,
  });

  /// O que aconteceu, na língua de quem lê.
  ///
  /// O evento vem primeiro porque é o que de fato mudou; a operação do agente
  /// cobre o que não tem evento com nome próprio; e o código cru, humanizado, é
  /// a última saída — melhor uma frase imperfeita que uma linha em branco.
  String get descricao =>
      _porEvento[evento] ?? _porOperacao[operacao] ?? _humanizar(evento);
}

const _porEvento = <String, String>{
  'contato_cadastrado': 'Cadastrou um contato',
  'contato_editado': 'Editou um contato',
  'contato_desativado': 'Tirou um contato da lista',
  'contato_reativado': 'Devolveu um contato à lista',
  'contato_gravado': 'Registrou um contato',
  'atendimento.iniciado_manualmente': 'Abriu uma conversa com um cliente',
  'mensagem.midia_enviada': 'Enviou um arquivo numa conversa',
  'etiqueta_criada': 'Criou uma etiqueta',
  'fluxo_criado': 'Criou um fluxo de atendimento',
  'fluxo_atualizado': 'Alterou um fluxo de atendimento',
  'fluxo_desativado': 'Desativou um fluxo de atendimento',
  'etapa_fluxo_criada': 'Criou uma coluna no quadro',
  'etapa_fluxo_atualizada': 'Alterou uma coluna do quadro',
  'etapa_fluxo_removida': 'Removeu uma coluna do quadro',
  'departamento_criado': 'Criou um departamento',
  'departamento_atualizado': 'Alterou um departamento',
  'departamento_desativado': 'Desativou um departamento',
  'treinamento_criado': 'Ensinou algo novo à IA',
  'treinamento_finalizado': 'Enviou um material para a IA',
  'treinamento_removido': 'Removeu um material da IA',
  'intent_criada': 'Criou uma intenção da IA',
  'intent_atualizada': 'Alterou uma intenção da IA',
  'intent_removida': 'Removeu uma intenção da IA',
  'tenant_config_updated': 'Alterou a configuração da conta',
  'tenant_invite_created': 'Convidou alguém para a equipe',
  'tenant_invite_resent': 'Reenviou um convite',
  'tenant_invite_revoked': 'Revogou um convite',
  'tenant_invite_accepted': 'Aceitou um convite',
  'tenant_user_role_change': 'Mudou o papel de um usuário',
  'tenant_user_flow_permissions_alteradas': 'Mudou os fluxos de um usuário',
  'whatsapp_instance.created': 'Criou uma conexão de WhatsApp',
  'whatsapp_instance.deleted': 'Removeu uma conexão de WhatsApp',
  'oauth.grant_revogado': 'Desconectou um aplicativo',
};

/// Operações de agente que não geram evento com nome próprio.
const _porOperacao = <String, String>{
  'SendOutboundMessage': 'Enviou uma mensagem a um cliente',
  'MoveAtendimentoEtapa': 'Moveu um atendimento de coluna',
  'SetAtendimentoStatus': 'Mudou a situação de um atendimento',
  'CreateNota': 'Anotou num atendimento',
  'AlternarEtiqueta': 'Mudou as etiquetas de um atendimento',
  'DefinirBotDaConversa': 'Ligou ou desligou a IA numa conversa',
  'IniciarAtendimentoManual': 'Abriu uma conversa com um cliente',
};

String _humanizar(String codigo) {
  final texto = codigo.replaceAll(RegExp(r'[._]+'), ' ').trim();
  if (texto.isEmpty) return 'Ação registrada';
  return texto[0].toUpperCase() + texto.substring(1);
}
