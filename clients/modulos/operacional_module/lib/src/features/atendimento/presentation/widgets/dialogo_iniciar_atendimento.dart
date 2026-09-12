import 'dart:async';

import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/contato_para_atendimento.dart';
import '../../domain/model/quadro.dart';
import '../../domain/parameters/iniciar_atendimento_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/kanban_state.dart';

/// C3 — abrir uma conversa com um cliente já cadastrado.
///
/// Até aqui um atendimento só nascia de uma mensagem que chegou: para procurar
/// o cliente era preciso sair do produto, escrever pelo WhatsApp e esperar a
/// resposta cair no quadro — e o histórico começava pela metade.
///
/// Devolve o id do atendimento aberto, ou `null` se a pessoa desistiu.
Future<int?> mostrarDialogoIniciarAtendimento(
  BuildContext context, {
  required KanbanViewModel quadro,
  required BuscarContatos buscarContatos,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _Dialogo(quadro: quadro, buscarContatos: buscarContatos),
  );
}

class _Dialogo extends StatefulWidget {
  final KanbanViewModel quadro;
  final BuscarContatos buscarContatos;

  const _Dialogo({required this.quadro, required this.buscarContatos});

  @override
  State<_Dialogo> createState() => _DialogoState();
}

class _DialogoState extends State<_Dialogo> {
  final _busca = TextEditingController();
  final _assunto = TextEditingController();

  Timer? _debounce;
  List<ContatoParaAtendimento> _achados = const [];
  ContatoParaAtendimento? _escolhido;
  int? _fluxoId;
  int? _etapaId;
  bool _procurando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _fluxoId = widget.quadro.fluxoId;
    // A primeira coluna do quadro é onde a conversa começa por padrão — é a
    // fila de entrada. Deixar em branco faria o operador decidir toda vez algo
    // que quase sempre é o mesmo.
    _etapaId = widget.quadro.colunas.isNotEmpty
        ? widget.quadro.colunas.first.id
        : null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    _assunto.dispose();
    super.dispose();
  }

  /// Espera a digitação parar antes de perguntar ao servidor.
  ///
  /// Sem isso, digitar "Maria" seriam cinco consultas — quatro delas para
  /// prefixos que ninguém queria ver.
  void _aoDigitar(String termo) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _procurar(termo),
    );
  }

  Future<void> _procurar(String termo) async {
    if (termo.trim().length < 2) {
      setState(() => _achados = const []);
      return;
    }
    setState(() => _procurando = true);
    try {
      final achados = await widget.buscarContatos(termo.trim());
      if (mounted) setState(() => _achados = achados);
    } catch (_) {
      // A busca é auxiliar: falhar aqui não derruba o diálogo. Uma mensagem de
      // erro no meio da lista atrapalharia mais do que ajudaria — a lista fica
      // vazia e a pessoa digita de novo.
      if (mounted) setState(() => _achados = const []);
    } finally {
      if (mounted) setState(() => _procurando = false);
    }
  }

  bool get _podeAbrir =>
      _escolhido != null && _fluxoId != null && _etapaId != null && !_enviando;

  Future<void> _abrir() async {
    if (!_podeAbrir) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });

    final resultado = await inject<IniciarAtendimentoUsecase>()(
      IniciarAtendimentoParameters(
        contatoId: _escolhido!.id,
        fluxoId: _fluxoId!,
        etapaInicialId: _etapaId!,
        assunto: _assunto.text.trim().isEmpty ? null : _assunto.text.trim(),
      ),
    );

    if (!mounted) return;
    switch (resultado) {
      case Success(:final value):
        // `jaExistia` muda o que se diz, não o que se faz: nos dois casos a
        // conversa certa abre. Anunciar "atendimento criado" para uma que já
        // estava aberta mandaria o operador procurar um cartão novo que não
        // existe.
        if (value.jaExistia) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este cliente já tinha uma conversa aberta. Abrindo ela.',
              ),
            ),
          );
        }
        Navigator.of(context).pop(value.atendimentoId);
      case Failure(:final error):
        setState(() {
          _enviando = false;
          _erro = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      title: const Text('Iniciar atendimento'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_erro != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.dangerSoft,
                    borderRadius: AppRadius.md,
                  ),
                  child: Text(
                    _erro!,
                    style: TextStyle(color: colors.danger, fontSize: 13),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                label: 'Cliente',
                hint: 'Procure por nome ou telefone',
                controller: _busca,
                onChanged: _aoDigitar,
              ),
              if (_procurando)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_escolhido != null)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle, color: colors.success),
                  title: Text(
                    _escolhido!.nome.isEmpty
                        ? _escolhido!.telefone
                        : _escolhido!.nome,
                  ),
                  subtitle: Text(_escolhido!.telefone),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Escolher outro cliente',
                    onPressed: () => setState(() => _escolhido = null),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final contato in _achados)
                        ListTile(
                          dense: true,
                          title: Text(
                            contato.nome.isEmpty
                                ? contato.telefone
                                : contato.nome,
                          ),
                          subtitle: Text(contato.telefone),
                          onTap: () => setState(() {
                            _escolhido = contato;
                            _achados = const [];
                          }),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _fluxoId,
                decoration: const InputDecoration(labelText: 'Quadro'),
                items: [
                  for (final fluxo in widget.quadro.fluxos)
                    DropdownMenuItem(
                      value: fluxo.id,
                      child: Text(fluxo.rotulo),
                    ),
                ],
                onChanged: (v) => setState(() => _fluxoId = v),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _etapaId,
                decoration: const InputDecoration(labelText: 'Começa em'),
                items: [
                  for (final ColunaDoQuadro coluna in widget.quadro.colunas)
                    DropdownMenuItem(
                      value: coluna.id,
                      child: Text(coluna.nome),
                    ),
                ],
                onChanged: (v) => setState(() => _etapaId = v),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Assunto (opcional)',
                hint: 'ex: renovação do contrato',
                controller: _assunto,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        PrimaryButton(
          label: 'Abrir conversa',
          expand: false,
          isLoading: _enviando,
          onPressed: _podeAbrir ? _abrir : null,
        ),
      ],
    );
  }
}
