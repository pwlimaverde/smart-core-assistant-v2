import 'package:dependencies_module/dependencies_module.dart';

import '../../../../permissao_do_treinamento.dart';
import '../../domain/model/ensaio.dart';
import '../controllers/ensaio_controllers.dart';

/// Testar pergunta.
///
/// A pergunta percorre o mesmo caminho de uma mensagem real de WhatsApp
/// (embed → busca no material → LLM), sem gravar atendimento nenhum. É o único
/// jeito de saber se o treinamento pegou sem usar um número de verdade e sujar
/// o histórico de um cliente.
class AbaEnsaio extends StatefulWidget {
  const AbaEnsaio({super.key});

  @override
  State<AbaEnsaio> createState() => _AbaEnsaioState();
}

class _AbaEnsaioState extends State<AbaEnsaio> {
  late final EnsaioController _controller;
  final _pergunta = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = inject<EnsaioController>();
  }

  @override
  void dispose() {
    _pergunta.dispose();
    super.dispose();
  }

  void _enviar() {
    final texto = _pergunta.text.trim();
    if (texto.isEmpty) return;
    _controller.testar(texto);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A pergunta passa pelo mesmo caminho de uma mensagem real. Nada é '
          'gravado: não cria atendimento nem contato.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _pergunta,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _enviar(),
                decoration: const InputDecoration(
                  labelText: 'Pergunta do cliente',
                  hintText: 'ex: vocês entregam no sábado?',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Testar'),
              onPressed: _enviar,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: ViewStateBuilder<EnsaioController, Ensaio>(
            controller: _controller,
            // Antes do primeiro teste não há erro nem resposta — só o convite.
            onInitial: (context) => const AppEmptyView(
              icon: Icons.science_outlined,
              title: 'Faça uma pergunta',
              subtitle:
                  'Escreva como um cliente escreveria, com as palavras '
                  'dele. É assim que a busca compara.',
            ),
            onError: (context, error) =>
                AppErrorView(message: error.message, onRetry: _enviar),
            onSuccess: (context, ensaio) => _Resultado(
              pergunta: _controller.ultimaPergunta,
              ensaio: ensaio,
              controller: _controller,
            ),
          ),
        ),
      ],
    );
  }
}

class _Resultado extends StatelessWidget {
  final String pergunta;
  final Ensaio ensaio;
  final EnsaioController controller;

  const _Resultado({
    required this.pergunta,
    required this.ensaio,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

    return ListView(
      children: [
        Text(
          '"$pergunta"',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: muted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Resposta',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(ensaio.resposta),
            ],
          ),
        ),
        // B9 (N10 E6): avaliar é curadoria — escreve —, então segue a mesma
        // permissão de ensinar. A `key` zera a avaliação a cada teste novo.
        if (controller.aceitaAvaliacao &&
            PermissaoDoTreinamento.podeAlterar()) ...[
          const SizedBox(height: AppSpacing.md),
          _AvaliacaoDoEnsaio(
            key: ValueKey('$pergunta\u0000${ensaio.resposta}'),
            ensaio: ensaio,
            controller: controller,
          ),
        ],
        if (ensaio.transferiria) ...[
          const SizedBox(height: AppSpacing.md),
          // Transferir é uma decisão diferente de responder: a conversa sairia
          // do bot e cairia numa fila.
          _Aviso(
            icone: Icons.call_split,
            cor: Theme.of(context).colorScheme.primary,
            texto: ensaio.fluxoTransferencia.isEmpty
                ? 'A IA transferiria esta conversa em vez de responder.'
                : 'A IA transferiria para "${ensaio.fluxoTransferencia}".',
          ),
        ],
        if (ensaio.semContexto) ...[
          const SizedBox(height: AppSpacing.md),
          // A resposta pode até parecer boa — o modelo inventa. É justamente
          // aqui que quem treina precisa ser avisado.
          const _Aviso(
            icone: Icons.warning_amber_outlined,
            cor: Colors.orange,
            texto:
                'Nenhum material e nenhuma intenção casaram com esta '
                'pergunta. O que veio acima não saiu do seu treinamento.',
          ),
        ],
        if (ensaio.comportamentoAplicado.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Intenção aplicada',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(ensaio.comportamentoAplicado),
          ),
        ],
        if (ensaio.trechos.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Material consultado',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final trecho in ensaio.trechos) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A semelhança explica por que este trecho entrou e outro
                  // não — sem ela, "respondeu errado" não tem por onde ser
                  // investigado.
                  Text(
                    '${trecho.semelhanca}% de semelhança',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(trecho.conteudo),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String texto;

  const _Aviso({required this.icone, required this.cor, required this.texto});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(texto, style: TextStyle(color: cor)),
          ),
        ],
      ),
    );
  }
}

/// B9 (N10 E6) — "a resposta ficou boa?", com a resposta correta quando não.
///
/// A correção é o que dá valor ao registro: um "ruim" sozinho diz que algo está
/// errado, a correção diz o quê. Por isso o campo abre ao escolher "Ruim", em vez
/// de ficar escondido atrás de outro clique.
class _AvaliacaoDoEnsaio extends StatefulWidget {
  final Ensaio ensaio;
  final EnsaioController controller;

  const _AvaliacaoDoEnsaio({
    super.key,
    required this.ensaio,
    required this.controller,
  });

  @override
  State<_AvaliacaoDoEnsaio> createState() => _AvaliacaoDoEnsaioState();
}

class _AvaliacaoDoEnsaioState extends State<_AvaliacaoDoEnsaio> {
  final _correcao = TextEditingController();
  bool _ruim = false;
  bool _enviando = false;
  bool _registrada = false;

  @override
  void dispose() {
    _correcao.dispose();
    super.dispose();
  }

  Future<void> _enviar({required bool boa}) async {
    setState(() => _enviando = true);
    final erro = await widget.controller.avaliar(
      ensaio: widget.ensaio,
      boa: boa,
      correcao: boa ? '' : _correcao.text,
    );
    if (!mounted) return;
    if (erro == null) {
      setState(() => _registrada = true);
      return;
    }
    setState(() => _enviando = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(erro.message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_registrada) {
      return Text(
        'Avaliação registrada. Ela orienta o que ajustar no treinamento.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('A resposta ficou boa?'),
            OutlinedButton.icon(
              icon: const Icon(Icons.thumb_up_outlined, size: 18),
              label: const Text('Boa'),
              onPressed: _enviando ? null : () => _enviar(boa: true),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.thumb_down_outlined, size: 18),
              label: const Text('Ruim'),
              onPressed: _enviando ? null : () => setState(() => _ruim = true),
            ),
          ],
        ),
        if (_ruim) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _correcao,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Resposta correta',
              hintText: 'Como a IA deveria ter respondido?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _enviando ? null : () => _enviar(boa: false),
            child: const Text('Enviar avaliação'),
          ),
        ],
      ],
    );
  }
}
