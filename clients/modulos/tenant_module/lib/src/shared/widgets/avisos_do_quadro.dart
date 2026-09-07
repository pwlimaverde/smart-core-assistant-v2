import 'package:dependencies_module/dependencies_module.dart';

import 'aviso_assinatura.dart';
import 'aviso_conexao.dart';

/// Empilha as faixas de aviso do topo do quadro.
///
/// O `avisoBuilder` do `operacional_module` aceita **um** widget, e há dois
/// avisos possíveis. Compor aqui, e não lá, mantém a regra que já valia: o
/// módulo operacional não conhece conexão nem cobrança — os dois são assunto do
/// `tenant_module`.
///
/// A ordem importa: **assinatura primeiro**. Se a conta está pendente, o
/// WhatsApp fora do ar é consequência, não causa — e resolver a cobrança é o que
/// destrava o resto. Cada faixa se esconde sozinha quando não tem o que dizer,
/// então na maior parte do tempo isto é um `Column` vazio.
final class AvisosDoQuadro extends StatelessWidget {
  const AvisosDoQuadro({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [AvisoAssinatura(), AvisoConexao()],
  );
}
