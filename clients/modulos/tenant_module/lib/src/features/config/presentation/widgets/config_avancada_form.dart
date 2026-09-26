import 'dart:convert';

import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/tenant_config.dart';

/// Configuração avançada do assistente: marca, região, comportamento,
/// tipos de entidade e prompts do negócio.
///
/// Tinha tudo guardado no banco e nenhuma tela para editar — só dava para
/// mudar por migração. É o que a v1 deixava ajustar no painel.
class ConfigAvancadaForm extends StatefulWidget {
  final ConfigAvancada avancada;

  /// Grava; devolve a mensagem de erro, ou `null` quando deu certo.
  final Future<String?> Function(
    ConfigAvancada avancada,
    Set<String> promptsRemovidos,
  )
  aoSalvar;

  /// Quem só lê vê os valores e não o botão de salvar.
  final bool podeSalvar;

  const ConfigAvancadaForm({
    required this.avancada,
    required this.aoSalvar,
    this.podeSalvar = true,
    super.key,
  });

  @override
  State<ConfigAvancadaForm> createState() => _ConfigAvancadaFormState();
}

class _ConfigAvancadaFormState extends State<ConfigAvancadaForm> {
  late final _marca = TextEditingController(text: widget.avancada.marca);
  late final _corPrimaria = TextEditingController(
    text: widget.avancada.corPrimaria,
  );
  late final _corSecundaria = TextEditingController(
    text: widget.avancada.corSecundaria,
  );
  late final _fuso = TextEditingController(text: widget.avancada.fuso);
  late final _idioma = TextEditingController(text: widget.avancada.idioma);
  late final _msgPesquisa = TextEditingController(
    text: widget.avancada.msgPesquisaSatisfacao,
  );
  late final _minutos = TextEditingController(
    text: widget.avancada.minutosInatividade?.toString() ?? '',
  );
  late final _tipos = TextEditingController(
    text: _formatarJson(widget.avancada.tiposDeEntidadeJson),
  );
  late bool? _analisePrevia = widget.avancada.analisePrevia;
  late bool? _pesquisa = widget.avancada.pesquisaSatisfacao;
  late bool? _transcricao = widget.avancada.transcricao;

  /// Um controller por prompt, na ordem em que aparecem.
  late final Map<String, TextEditingController> _prompts = {
    for (final e in widget.avancada.prompts.entries)
      e.key: TextEditingController(text: e.value),
  };
  final _removidos = <String>{};
  bool _salvando = false;

  static String _formatarJson(String bruto) {
    if (bruto.trim().isEmpty || bruto.trim() == '{}') return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(bruto));
    } on FormatException {
      return bruto;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _marca,
      _corPrimaria,
      _corSecundaria,
      _fuso,
      _idioma,
      _msgPesquisa,
      _minutos,
      _tipos,
      ..._prompts.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// O que a tela tem, validado. Devolve o erro a mostrar, se houver.
  (ConfigAvancada?, String?) _montar() {
    final tipos = _tipos.text.trim();
    if (tipos.isNotEmpty) {
      try {
        final v = jsonDecode(tipos);
        if (v is! Map && v is! List) {
          return (null, 'Tipos de entidade: use um objeto ou uma lista JSON.');
        }
      } on FormatException {
        return (null, 'Tipos de entidade: o JSON não é válido.');
      }
    }
    final cor = RegExp(r'^#[0-9a-fA-F]{6}$');
    for (final (nome, c) in [
      ('primária', _corPrimaria),
      ('secundária', _corSecundaria),
    ]) {
      final t = c.text.trim();
      if (t.isNotEmpty && !cor.hasMatch(t)) {
        return (null, 'Cor $nome: use o formato #RRGGBB.');
      }
    }
    final minutosTexto = _minutos.text.trim();
    final minutos = minutosTexto.isEmpty ? null : int.tryParse(minutosTexto);
    if (minutosTexto.isNotEmpty && (minutos == null || minutos < 0)) {
      return (null, 'Inatividade: informe minutos inteiros (0 = padrão).');
    }
    return (
      ConfigAvancada(
        tiposDeEntidadeJson: tipos,
        prompts: {
          for (final e in _prompts.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text,
        },
        marca: _marca.text.trim(),
        corPrimaria: _corPrimaria.text.trim(),
        corSecundaria: _corSecundaria.text.trim(),
        fuso: _fuso.text.trim(),
        idioma: _idioma.text.trim(),
        analisePrevia: _analisePrevia,
        pesquisaSatisfacao: _pesquisa,
        msgPesquisaSatisfacao: _msgPesquisa.text,
        minutosInatividade: minutos,
        transcricao: _transcricao,
      ),
      null,
    );
  }

  Future<void> _salvar() async {
    final messenger = ScaffoldMessenger.of(context);
    final (avancada, erro) = _montar();
    if (avancada == null) {
      messenger.showSnackBar(SnackBar(content: Text(erro!)));
      return;
    }
    // Prompt esvaziado conta como retirado: volta ao global.
    final removidos = {
      ..._removidos,
      for (final e in _prompts.entries)
        if (e.value.text.trim().isEmpty) e.key,
    };
    setState(() => _salvando = true);
    final falha = await widget.aoSalvar(avancada, removidos);
    if (!mounted) return;
    setState(() => _salvando = false);
    messenger.showSnackBar(
      SnackBar(content: Text(falha ?? 'Configuração avançada salva.')),
    );
  }

  Future<void> _adicionarPrompt() async {
    final disponiveis = promptsConhecidos.keys
        .where((k) => !_prompts.containsKey(k))
        .toList();
    if (disponiveis.isEmpty) return;
    final chave = await showDialog<String>(
      context: context,
      builder: (dialogo) => SimpleDialog(
        title: const Text('Qual prompt personalizar?'),
        children: [
          for (final k in disponiveis)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogo).pop(k),
              child: ListTile(
                dense: true,
                title: Text(promptsConhecidos[k]!),
                subtitle: Text(k),
              ),
            ),
        ],
      ),
    );
    if (chave == null) return;
    setState(() {
      _removidos.remove(chave);
      _prompts[chave] = TextEditingController();
    });
  }

  Widget _interruptor(
    String titulo,
    String ajuda,
    bool? valor,
    ValueChanged<bool> aoMudar,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(titulo),
      subtitle: Text(valor == null ? '$ajuda (usando o padrão)' : ajuda),
      value: valor ?? false,
      onChanged: widget.podeSalvar ? aoMudar : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuração avançada',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text('Marca', style: titulo),
          const SizedBox(height: 8),
          AppTextField(label: 'Nome da marca', controller: _marca),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Cor primária',
                  hint: '#315c28',
                  controller: _corPrimaria,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Cor secundária',
                  hint: '#1b1c1d',
                  controller: _corSecundaria,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Região', style: titulo),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Fuso horário',
                  hint: 'America/Fortaleza',
                  controller: _fuso,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Idioma',
                  hint: 'pt-br',
                  controller: _idioma,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Comportamento', style: titulo),
          _interruptor(
            'Análise prévia das mensagens',
            'Detecta intenção e dados do cliente antes de responder',
            _analisePrevia,
            (v) => setState(() => _analisePrevia = v),
          ),
          _interruptor(
            'Transcrever áudios',
            'Converte áudios recebidos em texto para a IA',
            _transcricao,
            (v) => setState(() => _transcricao = v),
          ),
          _interruptor(
            'Pesquisa de satisfação',
            'Pergunta a nota ao cliente ao encerrar',
            _pesquisa,
            (v) => setState(() => _pesquisa = v),
          ),
          AppTextField(
            label: 'Mensagem da pesquisa de satisfação',
            controller: _msgPesquisa,
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Encerrar conversa parada após (minutos)',
            hint: '0 ou em branco = padrão',
            controller: _minutos,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          Text('Tipos de entidade', style: titulo),
          const SizedBox(height: 4),
          Text(
            'Os dados que a IA procura nas mensagens. JSON: '
            '{"tipo": "descrição"} ou uma lista de nomes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('tipos-de-entidade'),
            controller: _tipos,
            minLines: 3,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Prompts do negócio', style: titulo)),
              if (widget.podeSalvar)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Personalizar prompt'),
                  onPressed: _adicionarPrompt,
                ),
            ],
          ),
          Text(
            'Valem só para este negócio, por cima dos prompts padrão. '
            'Esvaziar um prompt volta ao padrão.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_prompts.isEmpty)
            Text(
              'Nenhum prompt personalizado: o assistente usa os padrões.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          for (final e in _prompts.entries)
            ExpansionTile(
              key: ValueKey(e.key),
              tilePadding: EdgeInsets.zero,
              title: Text(promptsConhecidos[e.key] ?? e.key),
              subtitle: Text(e.key),
              trailing: widget.podeSalvar
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Voltar ao prompt padrão',
                      onPressed: () => setState(() {
                        _prompts.remove(e.key)?.dispose();
                        _removidos.add(e.key);
                      }),
                    )
                  : null,
              children: [
                TextField(
                  controller: e.value,
                  minLines: 4,
                  maxLines: 20,
                  readOnly: !widget.podeSalvar,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          const SizedBox(height: 24),
          if (widget.podeSalvar)
            PrimaryButton(
              label: _salvando ? 'Salvando…' : 'Salvar configuração avançada',
              onPressed: _salvando ? null : _salvar,
            ),
        ],
      ),
    );
  }
}
