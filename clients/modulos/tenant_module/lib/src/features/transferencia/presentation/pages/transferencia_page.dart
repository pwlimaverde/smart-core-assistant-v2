import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/permissoes.dart';
import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/transferencia.dart';
import '../controllers/transferencia_controller.dart';
import '../widgets/dialogo_regra.dart';

/// "Transferência para atendente" (plano ia-engine-jev).
///
/// Quando o bot passa a conversa para uma pessoa é decisão do negócio, e ela
/// vivia espalhada e escondida: no prompt de regras, na persona, no
/// comportamento de cada intenção. Aqui ela fica numa tela, em quatro partes:
/// os sinais automáticos, as regras do negócio (testáveis antes de valer), os
/// padrões e as últimas transferências com o motivo.
final class TransferenciaPage extends StatefulWidget {
  const TransferenciaPage({super.key});

  @override
  State<TransferenciaPage> createState() => _TransferenciaPageState();
}

class _TransferenciaPageState extends State<TransferenciaPage> {
  late final TransferenciaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<TransferenciaController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  bool get _podeAlterar => sessaoPodeAlterar('/tenant/transferencia');

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Transferência para atendente',
      drawer: const TenantDrawer(),
      actions: [
        if (_podeAlterar)
          IconButton(
            key: const ValueKey('gerar-sugestoes'),
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: 'Criar sugestões a partir do texto antigo',
            onPressed: _gerarSugestoes,
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar',
          onPressed: _controller.carregar,
        ),
      ],
      body: ViewStateBuilder<TransferenciaController, PainelTransferencia>(
        controller: _controller,
        onError: (context, error) =>
            AppErrorView(message: error.message, onRetry: _controller.carregar),
        onSuccess: (context, painel) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _AvisoDoMotor(motor: painel.config.motorAnalise),
            const SizedBox(height: AppSpacing.md),
            _Secao(
              titulo: 'Sinais automáticos',
              subtitulo:
                  'O bot percebe sozinho. Sensibilidade alta transfere mais '
                  'fácil; baixa, só quando está claro.',
              child: Column(
                children: [
                  for (final sinal in painel.config.sinais)
                    _LinhaDoSinal(
                      sinal: sinal,
                      podeAlterar: _podeAlterar,
                      onMudar: (novo) async {
                        final erro = await _controller.alterarSinal(novo);
                        if (erro != null) _avisar(erro.message);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Secao(
              titulo: 'Regras do negócio',
              subtitulo:
                  'Uma condição exata por regra, lida ao pé da letra: "o '
                  'cliente quer fechar o pedido", não "assuntos comerciais". '
                  'Toda regra nasce desligada — teste e ligue.',
              acao: _podeAlterar
                  ? FilledButton.icon(
                      key: const ValueKey('nova-regra'),
                      icon: const Icon(Icons.add),
                      label: const Text('Nova regra'),
                      onPressed: () => _editar(painel),
                    )
                  : null,
              child: painel.regras.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        'Nenhuma regra ainda. Crie uma, ou gere sugestões a '
                        'partir do texto antigo (botão no topo).',
                      ),
                    )
                  : Column(
                      children: [
                        for (final regra in painel.regras)
                          _LinhaDaRegra(
                            regra: regra,
                            painel: painel,
                            podeAlterar: _podeAlterar,
                            onEditar: () => _editar(painel, regra: regra),
                            onAlternar: (ativa) => _alternar(regra, ativa),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Secao(
              titulo: 'Padrões',
              subtitulo:
                  'Para onde vai a conversa quando a regra não diz, e o que o '
                  'cliente lê. A mensagem se edita na Configuração do Tenant.',
              child: _Padroes(
                painel: painel,
                podeAlterar: _podeAlterar,
                onFluxo: (id) async {
                  final erro = await _controller.definirFluxoPadrao(id);
                  if (erro != null) _avisar(erro.message);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Secao(
              titulo: 'Últimas transferências',
              subtitulo: 'O que a IA transferiu, e por quê.',
              child: painel.transferencias.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('Nenhuma transferência registrada ainda.'),
                    )
                  : Column(
                      children: [
                        for (final t in painel.transferencias)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.support_agent_outlined),
                            title: Text(t.motivoLegivel),
                            subtitle: Text(
                              '${DateFormat('dd/MM HH:mm').format(t.criadoEm)}'
                              ' · atendimento #${t.atendimentoId}'
                              '${t.fluxoNome.isEmpty ? '' : ' → ${t.fluxoNome}'}',
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editar(
    PainelTransferencia painel, {
    RegraDeTransferencia? regra,
  }) async {
    final resultado = await abrirDialogoRegra(
      context,
      regra: regra ?? const RegraDeTransferencia(),
      painel: painel,
      testar: (frase, r) => _controller.testar(frase: frase, regra: r),
    );
    if (resultado == null) return;
    final erro = await _controller.salvar(resultado);
    _avisar(
      erro?.message ??
          (resultado.nova
              ? 'Regra criada, desligada. Teste e ligue quando estiver certa.'
              : 'Regra salva.'),
    );
  }

  Future<void> _alternar(RegraDeTransferencia regra, bool ativa) async {
    if (!ativa) {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogo) => AlertDialog(
          title: Text('Desligar "${regra.nome}"?'),
          content: const Text(
            'A regra deixa de valer na próxima mensagem. Nada é apagado: '
            'dá para ligar de novo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogo).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogo).pop(true),
              child: const Text('Desligar'),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
    }
    final erro = await _controller.definirAtiva(regra, ativa: ativa);
    if (erro != null) _avisar(erro.message);
  }

  Future<void> _gerarSugestoes() async {
    final res = await _controller.gerarSugestoes();
    switch (res) {
      case Success(:final value):
        _avisar(
          value == 0
              ? 'Nada novo: o texto antigo não tem transferência que já não '
                    'esteja aqui.'
              : '$value sugestão(ões) criada(s), desligadas. Revise e ligue.',
        );
      case Failure(:final error):
        _avisar(error.message);
    }
  }
}

class _AvisoDoMotor extends StatelessWidget {
  final String motor;

  const _AvisoDoMotor({required this.motor});

  @override
  Widget build(BuildContext context) {
    final (icone, texto) = switch (motor) {
      'jev' => (
        Icons.check_circle_outline,
        'Estas regras estão valendo: o motor de IA novo decide as '
            'transferências por elas.',
      ),
      'sombra' => (
        Icons.visibility_outlined,
        'O motor de IA novo está em avaliação: ele registra o que faria com '
            'estas regras, mas quem decide ainda é o motor atual.',
      ),
      _ => (
        Icons.info_outline,
        'Estas regras passam a valer quando o motor de IA novo for ligado '
            'para o seu negócio. Até lá, dá para cadastrar e testar.',
      ),
    };
    return AppCard(
      child: Row(
        children: [
          Icon(icone, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final Widget child;
  final Widget? acao;

  const _Secao({
    required this.titulo,
    required this.subtitulo,
    required this.child,
    this.acao,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(titulo, style: tema.titleMedium)),
              ?acao,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitulo,
            style: tema.bodySmall?.copyWith(color: context.colors.fgMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _LinhaDoSinal extends StatelessWidget {
  final SinalAutomatico sinal;
  final bool podeAlterar;
  final ValueChanged<SinalAutomatico> onMudar;

  const _LinhaDoSinal({
    required this.sinal,
    required this.podeAlterar,
    required this.onMudar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          key: ValueKey('sinal-${sinal.nome}'),
          contentPadding: EdgeInsets.zero,
          title: Text(sinal.rotulo),
          subtitle: Text(sinal.explicacao),
          value: sinal.ativo,
          onChanged: podeAlterar
              ? (v) => onMudar(sinal.copyWith(ativo: v))
              : null,
        ),
        if (sinal.temSensibilidade && sinal.ativo)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _Sensibilidade(
                valor: sinal.sensibilidade,
                onMudar: podeAlterar
                    ? (s) => onMudar(sinal.copyWith(sensibilidade: s))
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _Sensibilidade extends StatelessWidget {
  final String valor;
  final ValueChanged<String>? onMudar;

  const _Sensibilidade({required this.valor, required this.onMudar});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'baixa', label: Text('Baixa')),
        ButtonSegment(value: 'media', label: Text('Média')),
        ButtonSegment(value: 'alta', label: Text('Alta')),
      ],
      selected: {valor},
      onSelectionChanged: onMudar == null ? null : (s) => onMudar!(s.first),
    );
  }
}

class _LinhaDaRegra extends StatelessWidget {
  final RegraDeTransferencia regra;
  final PainelTransferencia painel;
  final bool podeAlterar;
  final VoidCallback onEditar;
  final ValueChanged<bool> onAlternar;

  const _LinhaDaRegra({
    required this.regra,
    required this.painel,
    required this.podeAlterar,
    required this.onEditar,
    required this.onAlternar,
  });

  String get _gatilho => regra.gatilhoTipo == 'intencao'
      ? 'Intenção: ${regra.intencaoTag}'
      : 'Quando ${regra.condicao}';

  String get _destino {
    final quando = regra.momento == 'apos_coleta'
        ? 'depois de coletar ${regra.camposColeta.join(', ')}'
        : 'imediatamente';
    final para = switch (regra.destinoTipo) {
      'fluxo' =>
        painel.fluxos
                .where((f) => f.id == regra.destinoFluxoId)
                .map((f) => f.nome)
                .firstOrNull ??
            'fluxo ${regra.destinoFluxoId}',
      'setor_jev' => 'o setor que a IA escolher',
      _ => 'o fluxo padrão',
    };
    return '$quando → $para';
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    return ListTile(
      key: ValueKey('regra-${regra.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: onEditar,
      title: Row(
        children: [
          Flexible(child: Text(regra.nome, overflow: TextOverflow.ellipsis)),
          if (regra.sugestao) ...[
            const SizedBox(width: AppSpacing.xs),
            const Chip(
              label: Text('sugestão'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '$_gatilho\n$_destino',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
      ),
      isThreeLine: true,
      trailing: Tooltip(
        message: regra.ativa ? 'Valendo' : 'Desligada',
        child: Switch(
          value: regra.ativa,
          onChanged: podeAlterar ? onAlternar : null,
        ),
      ),
    );
  }
}

class _Padroes extends StatelessWidget {
  final PainelTransferencia painel;
  final bool podeAlterar;
  final ValueChanged<int?> onFluxo;

  const _Padroes({
    required this.painel,
    required this.podeAlterar,
    required this.onFluxo,
  });

  @override
  Widget build(BuildContext context) {
    final atual = painel.config.fluxoPadraoId;
    final existe = painel.fluxos.any((f) => f.id == atual);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int?>(
          key: const ValueKey('fluxo-padrao'),
          initialValue: existe ? atual : null,
          decoration: const InputDecoration(
            labelText: 'Fluxo de destino padrão',
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('O setor que a IA escolher'),
            ),
            for (final f in painel.fluxos)
              DropdownMenuItem<int?>(value: f.id, child: Text(f.nome)),
          ],
          onChanged: podeAlterar ? onFluxo : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Mensagem ao cliente na transferência',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          painel.config.msgTransferencia.isEmpty
              ? '(a mensagem padrão da plataforma)'
              : painel.config.msgTransferencia,
        ),
      ],
    );
  }
}
