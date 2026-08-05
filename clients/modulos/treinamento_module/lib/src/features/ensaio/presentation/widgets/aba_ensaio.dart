import 'package:dependencies_module/dependencies_module.dart';

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
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.colors.fgMuted),
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
              subtitle: 'Escreva como um cliente escreveria, com as palavras '
                  'dele. É assim que a busca compara.',
            ),
            onError: (context, error) => AppErrorView(
              message: error.message,
              onRetry: _enviar,
            ),
            onSuccess: (context, ensaio) => _Resultado(
              pergunta: _controller.ultimaPergunta,
              ensaio: ensaio,
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

  const _Resultado({required this.pergunta, required this.ensaio});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

    return ListView(
      children: [
        Text(
          '"$pergunta"',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: muted, fontStyle: FontStyle.italic),
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
            texto: 'Nenhum material e nenhuma intenção casaram com esta '
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
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: muted),
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
          Expanded(child: Text(texto, style: TextStyle(color: cor))),
        ],
      ),
    );
  }
}
