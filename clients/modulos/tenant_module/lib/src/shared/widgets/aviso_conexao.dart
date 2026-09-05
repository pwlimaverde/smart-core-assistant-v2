import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';

import '../../features/conexoes/domain/errors/conexoes_errors.dart';
import '../../features/conexoes/domain/model/conexao.dart';
import '../../features/conexoes/domain/usecases/conexoes_usecases.dart';
import '../../features/conexoes/domain/parameters/conexoes_parameters.dart';

/// Faixa que avisa, na primeira tela, que o WhatsApp saiu do ar.
///
/// O quadro parece normal quando a conexão cai — só não chega conversa
/// nenhuma. Sem este aviso, quem está atendendo leva horas para desconfiar, e o
/// caminho até a página de conexões não é óbvio para quem só usa a fila.
///
/// O servidor religa sozinho o que dá para religar (reconciliação periódica no
/// worker), então esta faixa é o caso que ele NÃO resolve: sessão recusada pelo
/// WhatsApp, que exige um QR novo com o celular em mãos. Por isso ela leva
/// direto para a tela de conexões em vez de oferecer um botão de "tentar de
/// novo" que não mudaria nada.
final class AvisoConexao extends StatefulWidget {
  const AvisoConexao({super.key});

  @override
  State<AvisoConexao> createState() => _AvisoConexaoState();
}

class _AvisoConexaoState extends State<AvisoConexao> {
  /// Conferir de minuto em minuto basta: a queda em si o servidor trata, e o
  /// que sobra aqui é um estado que só muda com ação humana.
  static const _intervalo = Duration(minutes: 1);

  Timer? _poll;
  List<Conexao> _fora = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_conferir());
    _poll = Timer.periodic(_intervalo, (_) => _conferir());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _conferir() async {
    final res = await inject<ListarConexoesUsecase>()(noParams);
    if (!mounted || res is! Success<List<Conexao>, ConexoesError>) return;

    // Estado do banco, que pode estar velho — por isso confere cada uma com o
    // provedor, igual à tela de conexões.
    final fora = <Conexao>[];
    for (final c in res.value) {
      final estado = await inject<EstadoPareamentoUsecase>()(
        ConexaoIdParameters(id: c.id),
      );
      final real = estado is Success<EstadoPareamento, ConexoesError>
          ? c.comEstado(estado.value.estado)
          : c;
      if (real.situacao != SituacaoConexao.conectada) fora.add(real);
    }

    if (!mounted) return;
    setState(() => _fora = fora);
  }

  @override
  Widget build(BuildContext context) {
    if (_fora.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final nomes = _fora.map((c) => c.nome).join(', ');
    final plural = _fora.length > 1;

    return Material(
      color: colors.warningSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_outlined, color: colors.warning),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                plural
                    ? '$nomes estão fora do ar. Enquanto isso, nenhuma mensagem '
                          'nova chega ao sistema.'
                    : '$nomes está fora do ar. Enquanto isso, nenhuma mensagem '
                          'nova chega ao sistema.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton(
              onPressed: () => context.go('/tenant/conexoes'),
              child: const Text('Reconectar'),
            ),
          ],
        ),
      ),
    );
  }
}
