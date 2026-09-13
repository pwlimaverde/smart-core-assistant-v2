import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart' hide AuthService;

import '../../../../shared/permissoes.dart';
import '../../domain/errors/integracoes_errors.dart';
import '../../domain/model/mcp_grant.dart';
import '../../domain/usecases/integracoes_usecases.dart';

/// B8 (doc 35-agentes F5) — a regra do convite, sem widget em volta.
///
/// Convida só quem tem **zero** aplicativos conectados e não dispensou. Sem saber
/// quantos há (`null`: a lista falhou ou nem carregou), não convida: insistir com
/// quem talvez já use o recurso é o incômodo que o plano manda evitar.
bool deveConvidarParaAgentes({
  required bool dispensado,
  required int? conectados,
}) => !dispensado && conectados == 0;

/// Chave do "dispensado". Por **usuário**, não por tenant: conectar um agente é
/// decisão pessoal, e o colega que dispensou não decide pelos outros.
String chaveConviteAgentesDispensado(int usuarioId) =>
    'integracoes.convite_agentes_dispensado.$usuarioId';

/// B8 — cartão dispensável do Painel: "você pode ligar um assistente de IA à
/// sua conta", com o caminho até a tela.
///
/// Sem modal nem tour, de propósito (plano F5): é útil para quem tem uma tarefa,
/// e interromper quem tem outra só irrita. Some sozinho quando não tem o que
/// dizer — inclusive quando o app não registrou o que ele precisa, como nos
/// testes de outras telas.
///
/// O "dispensado" fica no armazenamento local, por usuário: dispensar neste
/// computador não esconde o cartão em outro.
final class ConviteAgentes extends StatefulWidget {
  const ConviteAgentes({super.key});

  @override
  State<ConviteAgentes> createState() => _ConviteAgentesState();
}

class _ConviteAgentesState extends State<ConviteAgentes> {
  bool _mostrar = false;

  @override
  void initState() {
    super.initState();
    unawaited(_decidir());
  }

  String? get _chave {
    final usuario = usuarioDaSessao();
    return usuario == null ? null : chaveConviteAgentesDispensado(usuario);
  }

  Future<void> _decidir() async {
    final getIt = GetIt.instance;
    final chave = _chave;
    if (chave == null ||
        !getIt.isRegistered<ListMcpGrantsUsecase>() ||
        !getIt.isRegistered<LocalStorageService>()) {
      return;
    }
    final dispensado = inject<LocalStorageService>().read(chave) == '1';
    if (dispensado) return;

    final res = await inject<ListMcpGrantsUsecase>()(noParams);
    final conectados = res is Success<List<McpGrant>, IntegracoesError>
        ? res.value.length
        : null;
    if (!mounted) return;
    setState(
      () => _mostrar = deveConvidarParaAgentes(
        dispensado: dispensado,
        conectados: conectados,
      ),
    );
  }

  Future<void> _dispensar() async {
    setState(() => _mostrar = false);
    final chave = _chave;
    if (chave != null) {
      await inject<LocalStorageService>().write(chave, '1');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_mostrar) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ligue um assistente de IA à sua conta',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Claude, ChatGPT ou Cursor podem consultar seus atendimentos '
                  'e agir aqui, só com as permissões que você escolher.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.fgMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => context.go('/tenant/integracoes'),
                  child: const Text('Ver como conectar'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Dispensar',
            onPressed: _dispensar,
          ),
        ],
      ),
    );
  }
}
