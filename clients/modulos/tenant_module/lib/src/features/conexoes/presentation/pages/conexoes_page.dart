import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/permissoes.dart';
import '../../../../shared/widgets/tenant_drawer.dart';
import '../../../equipe/domain/model/equipe.dart';
import '../../../equipe/domain/usecases/equipe_usecases.dart';
import '../../domain/model/conexao.dart';
import '../controllers/conexoes_controllers.dart';
import '../widgets/detalhe_conexao_dialog.dart';
import '../widgets/pareamento_dialog.dart';

/// Conexões de WhatsApp do tenant.
///
/// Existe porque o onboarding cria a primeira conexão e depois disso não havia
/// mais nada: uma conexão que caísse deixava o tenant sem saída — sem ver o
/// estado, sem reconectar, sem trocar de aparelho.
final class ConexoesPage extends StatefulWidget {
  const ConexoesPage({super.key});

  @override
  State<ConexoesPage> createState() => _ConexoesPageState();
}

class _ConexoesPageState extends State<ConexoesPage> {
  late final ConexoesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<ConexoesController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Conexões de WhatsApp',
      drawer: const TenantDrawer(),
      actions: [
        if (sessaoPodeAlterar('/tenant/conexoes'))
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Nova conexão',
            onPressed: () => _novaConexao(context),
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ViewStateBuilder<ConexoesController, List<Conexao>>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.carregar,
          ),
          onSuccess: (context, itens) => itens.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppEmptyView(
                      title: 'Nenhuma conexão',
                      subtitle:
                          'Conecte um WhatsApp para começar a receber '
                          'mensagens dos seus clientes.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Sem este botão o tenant que remove a última conexão fica
                    // sem saída: o roteiro inicial, que criava a primeira, só
                    // roda uma vez.
                    if (sessaoPodeAlterar('/tenant/conexoes'))
                      SizedBox(
                        width: 260,
                        child: PrimaryButton(
                          label: 'Conectar WhatsApp',
                          onPressed: () => _novaConexao(context),
                        ),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Não há "editar", e a ausência precisa ser explicada.
                    //
                    // O nome é o identificador da instância no provedor:
                    // renomeá-lo desfaria o vínculo e exigiria parear de novo.
                    // Sem esta linha, quem procura o botão conclui que ele
                    // sumiu — e é só o botão que nunca deveria existir.
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'O nome identifica a conexão no provedor e por isso não '
                        'muda. Para usar outro, remova esta e conecte de novo '
                        '— com QR novo.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.fgMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: itens.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        // O context do item não abre diálogos: ele é desmontado
                        // quando a lista recarrega.
                        itemBuilder: (_, i) => _Linha(
                          conexao: itens[i],
                          controller: _controller,
                          abrirPareamento: _abrirPareamento,
                          abrirDetalhe: _abrirDetalhe,
                          escolherDepartamento: _escolherDepartamento,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// A caixa de pareamento é aberta a partir da PÁGINA, não da linha da lista:
  /// a linha é desmontada assim que a lista recarrega, e o `context` dela morre
  /// junto — a página sobrevive à volta toda.
  Future<void> _abrirPareamento(int id, String nome) async {
    if (!mounted) return;
    await mostrarPareamento(
      context,
      controller: _controller,
      id: id,
      nome: nome,
    );
  }

  /// P7 — o detalhe, aberto pela PÁGINA pelo mesmo motivo do pareamento: a
  /// linha é desmontada quando a lista recarrega e leva o `context` junto.
  Future<void> _abrirDetalhe(int id) async {
    if (!mounted) return;
    await mostrarDetalheDaConexao(context, controller: _controller, id: id);
  }

  /// P7 — para qual departamento este número roteia.
  ///
  /// A lista de departamentos vem da equipe, que é do mesmo módulo. Sem
  /// nenhum cadastrado a caixa diz isso em vez de abrir vazia: o caminho é
  /// criar o departamento primeiro, e a tela precisa apontá-lo.
  Future<void> _escolherDepartamento(Conexao conexao) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await inject<CarregarEquipeUsecase>()(noParams);
    if (!mounted) return;

    final departamentos = switch (res) {
      Success(:final value) => value.departamentos.where((d) => d.ativo).toList(),
      Failure() => const <Departamento>[],
    };
    if (departamentos.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum departamento ativo. Crie um em Equipe para poder rotear '
            'por número.',
          ),
        ),
      );
      return;
    }

    // Um par, e não um `Departamento` de mentira: "nenhum" é uma escolha
    // legítima aqui, e inventar um registro com id 0 para representá-la faria
    // um objeto de domínio que não corresponde a nada no banco.
    final escolhido = await showDialog<(int, String)>(
      context: context,
      builder: (dialogo) => SimpleDialog(
        title: Text('Para onde "${conexao.nome}" manda conversa?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogo).pop((0, '')),
            child: const Text('Nenhum (usa o primeiro fluxo ativo)'),
          ),
          for (final d in departamentos)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogo).pop((d.id, d.nome)),
              child: Text(d.nome),
            ),
        ],
      ),
    );
    if (escolhido == null) return;

    final resultado = await _controller.definirDepartamento(
      id: conexao.id,
      departamentoId: escolhido.$1,
      departamentoNome: escolhido.$2,
    );
    if (resultado case Failure(:final error)) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Cria a conexão e emenda direto no pareamento: o nome sozinho não serve de
  /// nada — sem ler o QR em seguida a instância nasce e fica pendurada.
  Future<void> _novaConexao(BuildContext context) async {
    final nome = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => DialogoComCampos(
        campos: [nome],
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nova conexão'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Dê um nome para identificar este aparelho — por exemplo, '
                  '"atendimento" ou "vendas".',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(controller: nome, label: 'Nome da conexão'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final texto = nome.text.trim();
    if (texto.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await _controller.criar(texto);
    if (!context.mounted) return;

    switch (res) {
      case Success(:final value):
        await _abrirPareamento(value.id, value.nome);
      case Failure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _Linha extends StatelessWidget {
  final Conexao conexao;
  final ConexoesController controller;

  /// Aberta pela página: ver `_abrirPareamento`.
  final Future<void> Function(int id, String nome) abrirPareamento;

  /// P7 — também da página, pelo mesmo motivo.
  final Future<void> Function(int id) abrirDetalhe;
  final Future<void> Function(Conexao conexao) escolherDepartamento;

  const _Linha({
    required this.conexao,
    required this.controller,
    required this.abrirPareamento,
    required this.abrirDetalhe,
    required this.escolherDepartamento,
  });

  @override
  Widget build(BuildContext context) {
    final situacao = conexao.situacao;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      conexao.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Selo(situacao: situacao),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  conexao.telefone.isEmpty
                      ? situacao.explicacao
                      : '${conexao.telefone} · ${situacao.explicacao}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.fgMuted,
                  ),
                ),
                // P7 — para onde este número manda conversa. Sem o rótulo,
                // descobrir por que uma conversa caiu na fila errada exigia
                // abrir o banco.
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.call_split,
                      size: 14,
                      color: context.colors.fgMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      conexao.departamentoId == 0
                          ? 'Sem departamento — entra no primeiro fluxo ativo'
                          : 'Entra no fluxo de ${conexao.departamentoNome}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.fgMuted,
                      ),
                    ),
                  ],
                ),
                // O estado desligado precisa ser visível no cartão, e não só no
                // interruptor: quem abre a tela para entender por que o bot
                // parou tem que achar a resposta aqui.
                if (!conexao.respostaBot) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 14,
                        color: context.colors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Resposta automática desligada',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // D3 — o interruptor do bot. Vale mesmo com a conexão fora do ar: o
          // dono desliga a IA antes de reconectar justamente para atender à mão
          // sem que o robô responda no meio.
          Tooltip(
            message: conexao.respostaBot
                ? 'A IA responde automaticamente nesta conexão'
                : 'A IA não responde nesta conexão',
            child: Switch(
              value: conexao.respostaBot,
              // Visível para todos, porque diz como a conexão está; mudar é do
              // admin — calar a IA da conexão vale para o tenant inteiro.
              onChanged: sessaoEhAdmin()
                  ? (v) => _alternarBot(context, v)
                  : null,
            ),
          ),
          // O QR é a saída quando a sessão foi desfeita do lado do WhatsApp —
          // e era um caminho que só existia ao CRIAR a conexão. Depois disso a
          // tela oferecia "Reconectar", que não resolve pareamento perdido: o
          // aparelho foi desvinculado, e nenhuma reconexão o traz de volta.
          //
          // Aparece primeiro, e rotulado, quando a conexão está aguardando
          // leitura: é a ação que de fato conserta.
          if (sessaoPodeAlterar('/tenant/conexoes') &&
              (situacao == SituacaoConexao.conectando ||
                  situacao == SituacaoConexao.desconectada))
            TextButton.icon(
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('Ler QR code'),
              onPressed: () => abrirPareamento(conexao.id, conexao.nome),
            ),
          // Reconectar só faz sentido quando não está conectada — oferecer no
          // estado bom convidaria a derrubar uma conexão que funciona.
          if (sessaoPodeAlterar('/tenant/conexoes') &&
              situacao != SituacaoConexao.conectada)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconectar',
              onPressed: () => _reconectar(context),
            ),
          // P7 — o resto mora num menu: o cartão já tem interruptor, QR,
          // reconectar e remover, e mais dois botões soltos viram uma fileira
          // de ícones que ninguém lê.
          PopupMenuButton<String>(
            tooltip: 'Mais ações',
            onSelected: (opcao) => switch (opcao) {
              'detalhe' => abrirDetalhe(conexao.id),
              'departamento' => escolherDepartamento(conexao),
              'desconectar' => _desconectar(context),
              _ => Future<void>.value(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'detalhe',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Detalhe da conexão'),
                ),
              ),
              if (sessaoPodeAlterar('/tenant/conexoes'))
                const PopupMenuItem(
                  value: 'departamento',
                  child: ListTile(
                    leading: Icon(Icons.call_split),
                    title: Text('Departamento'),
                  ),
                ),
              // Só faz sentido no que ainda está de pé: pedir logout de uma
              // sessão já caída não tem efeito nenhum e confunde.
              if (sessaoPodeAlterar('/tenant/conexoes') &&
                  conexao.situacao != SituacaoConexao.desconectada)
                const PopupMenuItem(
                  value: 'desconectar',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Encerrar a sessão'),
                  ),
                ),
            ],
          ),
          if (sessaoPodeAlterar('/tenant/conexoes'))
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover conexão',
              onPressed: () => _remover(context),
            ),
        ],
      ),
    );
  }

  /// P7 — encerra a sessão sem apagar a conexão.
  ///
  /// Confirma sempre: o número sai do ar na hora, e quem esbarrou no item do
  /// menu descobriria pelo silêncio das mensagens que pararam de chegar.
  Future<void> _desconectar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('Encerrar a sessão de "${conexao.nome}"?'),
        content: const Text(
          'O número para de receber mensagens até alguém ler um QR novo. A '
          'conexão e todo o histórico continuam aqui — diferente de remover.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    final res = await controller.desconectar(conexao.id);
    if (res case Failure(:final error)) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Liga/desliga a IA da conexão.
  ///
  /// Confirma só ao DESLIGAR: ligar de volta é reversível e inofensivo, mas
  /// desligar cala o atendimento automático de um número inteiro — e quem
  /// esbarrou no interruptor sem querer não descobriria pelo silêncio.
  Future<void> _alternarBot(BuildContext context, bool habilitar) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!habilitar) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Desligar a resposta automática?'),
          content: Text(
            'A IA deixa de responder todas as conversas de "${conexao.nome}". '
            'As mensagens continuam chegando normalmente — só não são '
            'respondidas sozinhas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Desligar'),
            ),
          ],
        ),
      );
      if (confirmou != true) return;
    }

    final res = await controller.definirRespostaBot(conexao.id, habilitar);
    if (res case Failure(:final error)) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _reconectar(BuildContext context) async {
    // Resolvido antes do await: reconectar recarrega a lista e desmonta esta
    // linha antes de a resposta chegar — inclusive o `context` dela.
    final messenger = ScaffoldMessenger.of(context);
    final res = await controller.reconectar(conexao.id);

    switch (res) {
      // A sessão pode voltar sozinha (o aparelho ainda está pareado) ou exigir
      // um QR novo. Como não dá para saber antes, abre a caixa de pareamento:
      // se o provedor reconectar sem código, ela mesma anuncia e fecha.
      case Success():
        await abrirPareamento(conexao.id, conexao.nome);
      case Failure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _remover(BuildContext context) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remover "${conexao.nome}"?'),
        content: const Text(
          'As mensagens já recebidas continuam no histórico, mas esta conexão '
          'para de receber novas. Isto não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await controller.remover(conexao.id);

    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (res) {
          Success() => 'Conexão removida.',
          Failure(:final error) => error.message,
        }),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final SituacaoConexao situacao;

  const _Selo({required this.situacao});

  @override
  Widget build(BuildContext context) {
    final cor = switch (situacao) {
      SituacaoConexao.conectada => context.colors.success,
      SituacaoConexao.conectando => Colors.orange,
      SituacaoConexao.desconectada => Theme.of(context).colorScheme.error,
      SituacaoConexao.desconhecida => context.colors.fgMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        situacao.rotulo,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cor),
      ),
    );
  }
}
