import 'dart:convert';

import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

import '../../domain/model/ficha.dart';
import '../controllers/ficha_controller.dart';

/// Preenche (ou apaga) um campo do cartão na ficha (N9 E13).
///
/// O controle muda com o tipo: um campo de lista vira seletor, um booleano
/// vira dois botões, uma data abre o calendário. Um `TextField` para tudo
/// jogaria no operador o trabalho de acertar o formato — e é justamente o
/// formato que o servidor recusa.
Future<void> abrirEdicaoDeValor(
  BuildContext context,
  ValorCampo campo,
  FichaController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _DialogoValor(campo: campo, controller: controller),
  );
}

class _DialogoValor extends StatefulWidget {
  final ValorCampo campo;
  final FichaController controller;

  const _DialogoValor({required this.campo, required this.controller});

  @override
  State<_DialogoValor> createState() => _DialogoValorState();
}

class _DialogoValorState extends State<_DialogoValor> {
  late final TextEditingController _texto;
  String? _opcao;
  bool _booleano = false;
  DateTime? _data;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final bruto = _semAspas(widget.campo.valorJson);
    _texto = TextEditingController(text: bruto);
    _opcao = bruto.isEmpty ? null : bruto;
    _booleano = bruto == 'true';
    _data = DateTime.tryParse(bruto);
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  static String _semAspas(String v) {
    if (v.isEmpty || v == 'null') return '';
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      return v.substring(1, v.length - 1);
    }
    return v;
  }

  /// O valor na forma que o servidor espera para o tipo.
  String? _valorJson() {
    switch (widget.campo.tipo) {
      case 'numero':
        final n = num.tryParse(_texto.text.trim().replaceAll(',', '.'));
        if (n == null) return null;
        return n.toString();
      case 'booleano':
        return _booleano.toString();
      case 'data':
        final d = _data;
        if (d == null) return null;
        // AAAA-MM-DD, que é o que o servidor aceita — e o único formato sem
        // ambiguidade entre dia e mês.
        return jsonEncode(
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}',
        );
      case 'lista':
        final o = _opcao;
        return o == null ? null : jsonEncode(o);
      default:
        final t = _texto.text.trim();
        return t.isEmpty ? null : jsonEncode(t);
    }
  }

  Future<void> _salvar({bool apagando = false}) async {
    // `null` explícito ≠ campo em branco: apagar é uma decisão, e o servidor a
    // respeita — a IA não repreenche o que alguém tirou.
    final valor = apagando ? 'null' : _valorJson();
    if (valor == null) {
      setState(() => _erro = 'Informe um valor válido para este campo.');
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });

    final falha = await widget.controller.definirValorCampo(
      campoId: widget.campo.campoId,
      valorJson: valor,
    );

    if (!mounted) return;
    if (falha != null) {
      setState(() {
        _salvando = false;
        _erro = falha.message;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final campo = widget.campo;

    return AlertDialog(
      title: Text(campo.nome),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (campo.descricao.isNotEmpty) ...[
              Text(
                campo.descricao,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_erro != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.colors.dangerSoft,
                  borderRadius: AppRadius.md,
                ),
                child: Text(
                  _erro!,
                  style: TextStyle(color: context.colors.danger, fontSize: 13),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _controle(context),
            // Quem preencheu importa: um valor que a IA deduziu merece um
            // olhar antes de virar decisão.
            if (campo.veioDaIa && campo.preenchido) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: context.colors.accent,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Preenchido pela IA com '
                      '${(campo.confianca * 100).round()}% de confiança. '
                      'Ao salvar, passa a valer o que você escreveu.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (campo.preenchido)
          TextButton(
            onPressed: _salvando ? null : () => _salvar(apagando: true),
            child: const Text('Apagar'),
          ),
        TextButton(
          onPressed: _salvando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        PrimaryButton(
          label: 'Salvar',
          expand: false,
          isLoading: _salvando,
          onPressed: _salvando ? null : _salvar,
        ),
      ],
    );
  }

  Widget _controle(BuildContext context) {
    final campo = widget.campo;

    return switch (campo.tipo) {
      'lista' => DropdownButtonFormField<String>(
        initialValue: _opcao,
        decoration: const InputDecoration(labelText: 'Escolha'),
        items: [
          for (final o in campo.opcoes)
            DropdownMenuItem(value: o.id, child: Text(o.rotulo)),
        ],
        onChanged: (v) => setState(() => _opcao = v),
      ),
      'booleano' => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _booleano,
        title: Text(_booleano ? 'Sim' : 'Não'),
        onChanged: (v) => setState(() => _booleano = v),
      ),
      'data' => Row(
        children: [
          Expanded(
            child: Text(
              _data == null
                  ? 'Nenhuma data escolhida'
                  : '${_data!.day.toString().padLeft(2, '0')}/'
                        '${_data!.month.toString().padLeft(2, '0')}/'
                        '${_data!.year}',
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: const Text('Escolher'),
            onPressed: () async {
              final hoje = DateTime.now();
              final escolhida = await showDatePicker(
                context: context,
                initialDate: _data ?? hoje,
                firstDate: DateTime(hoje.year - 5),
                lastDate: DateTime(hoje.year + 5),
              );
              if (escolhida != null) setState(() => _data = escolhida);
            },
          ),
        ],
      ),
      'numero' => AppTextField(
        label: 'Valor',
        hint: 'só números',
        controller: _texto,
        keyboardType: TextInputType.number,
      ),
      _ => AppTextField(label: 'Valor', controller: _texto),
    };
  }
}
