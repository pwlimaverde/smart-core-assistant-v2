import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/errors/transferencia_errors.dart';
import '../../domain/model/transferencia.dart';

typedef TestarRegra =
    Future<ReturnSuccessOrError<ResultadoTesteRegra, TransferenciaError>>
    Function(String frase, RegraDeTransferencia regra);

List<String> _linhas(String texto) =>
    texto.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

/// Cria ou edita uma regra. Devolve a regra a salvar, ou `null` se cancelou.
///
/// O teste fica dentro do formulário de propósito: a condição é lida ao pé da
/// letra, e quem escreve precisa ver na hora se "pode fechar" dispara e "só
/// queria o prazo" não.
Future<RegraDeTransferencia?> abrirDialogoRegra(
  BuildContext context, {
  required RegraDeTransferencia regra,
  required PainelTransferencia painel,
  required TestarRegra testar,
}) {
  return showDialog<RegraDeTransferencia>(
    context: context,
    builder: (_) => _DialogoRegra(regra: regra, painel: painel, testar: testar),
  );
}

class _DialogoRegra extends StatefulWidget {
  final RegraDeTransferencia regra;
  final PainelTransferencia painel;
  final TestarRegra testar;

  const _DialogoRegra({
    required this.regra,
    required this.painel,
    required this.testar,
  });

  @override
  State<_DialogoRegra> createState() => _DialogoRegraState();
}

class _DialogoRegraState extends State<_DialogoRegra> {
  late final TextEditingController _nome;
  late final TextEditingController _condicao;
  late final TextEditingController _sim;
  late final TextEditingController _nao;
  late final TextEditingController _mensagem;
  final _frase = TextEditingController();

  late String _gatilho;
  late String _intencao;
  late String _momento;
  late Set<String> _campos;
  late String _destino;
  int? _fluxo;
  late String _sensibilidade;

  String? _erro;
  bool _testando = false;
  ResultadoTesteRegra? _resultado;
  String? _erroTeste;

  @override
  void initState() {
    super.initState();
    final r = widget.regra;
    _nome = TextEditingController(text: r.nome);
    _condicao = TextEditingController(text: r.condicao);
    _sim = TextEditingController(text: r.exemplosSim.join('\n'));
    _nao = TextEditingController(text: r.exemplosNao.join('\n'));
    _mensagem = TextEditingController(text: r.mensagem);
    _gatilho = r.gatilhoTipo;
    _intencao = r.intencaoTag;
    _momento = r.momento;
    _campos = r.camposColeta.toSet();
    _destino = r.destinoTipo;
    _fluxo = r.destinoFluxoId;
    _sensibilidade = r.sensibilidade;
  }

  @override
  void dispose() {
    for (final c in [_nome, _condicao, _sim, _nao, _mensagem, _frase]) {
      c.dispose();
    }
    super.dispose();
  }

  RegraDeTransferencia _montar() => RegraDeTransferencia(
    id: widget.regra.id,
    nome: _nome.text.trim(),
    gatilhoTipo: _gatilho,
    condicao: _gatilho == 'condicao' ? _condicao.text.trim() : '',
    intencaoTag: _gatilho == 'intencao' ? _intencao : '',
    exemplosSim: _linhas(_sim.text),
    exemplosNao: _linhas(_nao.text),
    momento: _momento,
    camposColeta: _momento == 'apos_coleta' ? _campos.toList() : const [],
    destinoTipo: _destino,
    destinoFluxoId: _destino == 'fluxo' ? _fluxo : null,
    mensagem: _mensagem.text.trim(),
    sensibilidade: _sensibilidade,
    ativa: widget.regra.ativa,
    sugestao: widget.regra.sugestao,
  );

  /// O mesmo que o servidor confere, dito antes de ir até ele.
  String? _validar(RegraDeTransferencia r) {
    if (r.nome.isEmpty) return 'Dê um nome à regra.';
    if (r.gatilhoTipo == 'condicao' && r.condicao.length < 10) {
      return 'Descreva a condição numa frase exata.';
    }
    if (r.gatilhoTipo == 'intencao' && r.intencaoTag.isEmpty) {
      return 'Escolha a intenção.';
    }
    if (r.momento == 'apos_coleta' && r.camposColeta.isEmpty) {
      return 'Escolha os campos a coletar antes de transferir.';
    }
    if (r.destinoTipo == 'fluxo' && r.destinoFluxoId == null) {
      return 'Escolha o fluxo de destino.';
    }
    return null;
  }

  Future<void> _rodarTeste() async {
    final frase = _frase.text.trim();
    if (frase.isEmpty) return;
    final regra = _montar();
    if (regra.condicao.length < 10) {
      setState(() => _erroTeste = 'Escreva a condição antes de testar.');
      return;
    }
    setState(() {
      _testando = true;
      _erroTeste = null;
      _resultado = null;
    });
    final res = await widget.testar(frase, regra);
    if (!mounted) return;
    setState(() {
      _testando = false;
      switch (res) {
        case Success(:final value):
          _resultado = value;
        case Failure(:final error):
          _erroTeste = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final painel = widget.painel;
    final muted = context.colors.fgMuted;
    return AlertDialog(
      title: Text(
        widget.regra.nova ? 'Nova regra de transferência' : 'Editar regra',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('regra-nome'),
                controller: _nome,
                autofocus: widget.regra.nova,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  hintText: 'Fechar pedido',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'condicao', label: Text('Condição')),
                  ButtonSegment(value: 'intencao', label: Text('Intenção')),
                ],
                selected: {_gatilho},
                onSelectionChanged: (s) => setState(() => _gatilho = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_gatilho == 'condicao') ...[
                TextField(
                  key: const ValueKey('regra-condicao'),
                  controller: _condicao,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Quando transferir (uma frase exata)',
                    hintText: 'O cliente quer fechar ou confirmar um pedido',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sim,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Frases que transferem',
                          hintText: 'uma por linha',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _nao,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Frases que NÃO transferem',
                          hintText: 'uma por linha',
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                DropdownButtonFormField<String>(
                  key: const ValueKey('regra-intencao'),
                  initialValue: painel.intencoes.contains(_intencao)
                      ? _intencao
                      : null,
                  decoration: const InputDecoration(labelText: 'Intenção'),
                  items: [
                    for (final i in painel.intencoes)
                      DropdownMenuItem(value: i, child: Text(i)),
                  ],
                  onChanged: (v) => setState(() => _intencao = v ?? ''),
                ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _momento,
                decoration: const InputDecoration(labelText: 'Quando'),
                items: const [
                  DropdownMenuItem(
                    value: 'imediato',
                    child: Text('Imediatamente'),
                  ),
                  DropdownMenuItem(
                    value: 'apos_coleta',
                    child: Text('Depois de coletar campos do cartão'),
                  ),
                ],
                onChanged: (v) => setState(() => _momento = v ?? 'imediato'),
              ),
              if (_momento == 'apos_coleta') ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final c in painel.campos)
                      FilterChip(
                        label: Text(c.nome),
                        selected: _campos.contains(c.slug),
                        onSelected: (v) => setState(
                          () =>
                              v ? _campos.add(c.slug) : _campos.remove(c.slug),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _destino,
                decoration: const InputDecoration(labelText: 'Para onde'),
                items: const [
                  DropdownMenuItem(
                    value: 'padrao',
                    child: Text('O fluxo padrão'),
                  ),
                  DropdownMenuItem(
                    value: 'setor_jev',
                    child: Text('O setor que a IA escolher'),
                  ),
                  DropdownMenuItem(value: 'fluxo', child: Text('Um fluxo')),
                ],
                onChanged: (v) => setState(() => _destino = v ?? 'padrao'),
              ),
              if (_destino == 'fluxo')
                DropdownButtonFormField<int>(
                  key: const ValueKey('regra-fluxo'),
                  initialValue: painel.fluxos.any((f) => f.id == _fluxo)
                      ? _fluxo
                      : null,
                  decoration: const InputDecoration(labelText: 'Fluxo'),
                  items: [
                    for (final f in painel.fluxos)
                      DropdownMenuItem(value: f.id, child: Text(f.nome)),
                  ],
                  onChanged: (v) => setState(() => _fluxo = v),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _mensagem,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mensagem ao cliente (opcional)',
                  hintText: 'Vazio = a mensagem padrão de transferência',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Sensibilidade',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'baixa', label: Text('Baixa')),
                  ButtonSegment(value: 'media', label: Text('Média')),
                  ButtonSegment(value: 'alta', label: Text('Alta')),
                ],
                selected: {_sensibilidade},
                onSelectionChanged: (s) =>
                    setState(() => _sensibilidade = s.first),
              ),
              if (_gatilho == 'condicao') ...[
                const Divider(height: AppSpacing.xl),
                Text('Testar', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  'Escreva uma mensagem como o cliente mandaria. Nada é gravado.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: muted),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('testar-frase'),
                        controller: _frase,
                        onSubmitted: (_) => _rodarTeste(),
                        decoration: const InputDecoration(
                          hintText: 'pode fechar',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton(
                      key: const ValueKey('testar-regra'),
                      onPressed: _testando ? null : _rodarTeste,
                      child: _testando
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Testar'),
                    ),
                  ],
                ),
                if (_resultado case final r?)
                  Padding(
                    key: const ValueKey('resultado-teste'),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      '${r.dispararia ? 'Transferiria' : 'Não transferiria'} — '
                      '${(r.probabilidade * 100).round()}% '
                      '(limiar ${(r.limiar * 100).round()}%)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: r.dispararia
                            ? Theme.of(context).colorScheme.primary
                            : muted,
                      ),
                    ),
                  ),
                if (_erroTeste case final e?)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      e,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
              if (_erro case final e?)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    e,
                    key: const ValueKey('erro-regra'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('salvar-regra'),
          onPressed: () {
            final regra = _montar();
            final erro = _validar(regra);
            if (erro != null) {
              setState(() => _erro = erro);
              return;
            }
            Navigator.of(context).pop(regra);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
