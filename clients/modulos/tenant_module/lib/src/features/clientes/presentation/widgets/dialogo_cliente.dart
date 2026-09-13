import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/cliente.dart';
import '../controllers/clientes_controllers.dart';

/// B10 (N11 E5) — cadastrar um cliente.
Future<void> abrirCadastroDeCliente(
  BuildContext context,
  ClientesController controller,
) => _abrir(context, controller, null);

/// B10 — corrigir o cadastro de um cliente.
Future<void> abrirEdicaoDeCliente(
  BuildContext context,
  Cliente cliente,
  ClientesController controller,
) => _abrir(context, controller, cliente);

Future<void> _abrir(
  BuildContext context,
  ClientesController controller,
  Cliente? existente,
) {
  final d = existente?.dados;
  TextEditingController campo(String? valor) =>
      TextEditingController(text: valor ?? '');
  final nomeFantasia = campo(d?.nomeFantasia);
  final razaoSocial = campo(d?.razaoSocial);
  final cnpj = campo(d?.cnpj == null ? null : formatarCnpj(d!.cnpj));
  final cpf = campo(d?.cpf == null ? null : formatarCpf(d!.cpf));
  final telefone = campo(d?.telefone);
  final site = campo(d?.site);
  final ramo = campo(d?.ramoAtividade);
  final observacoes = campo(d?.observacoes);
  final cep = campo(d?.cep);
  final logradouro = campo(d?.logradouro);
  final numero = campo(d?.numero);
  final complemento = campo(d?.complemento);
  final bairro = campo(d?.bairro);
  final cidade = campo(d?.cidade);
  final uf = campo(d?.uf);
  var tipo = d?.tipo.isNotEmpty == true ? d!.tipo : 'pj';
  var salvando = false;
  String? erro;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [
        nomeFantasia,
        razaoSocial,
        cnpj,
        cpf,
        telefone,
        site,
        ramo,
        observacoes,
        cep,
        logradouro,
        numero,
        complemento,
        bairro,
        cidade,
        uf,
      ],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setDialogState) {
          Widget secao(String titulo) => Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Text(titulo, style: Theme.of(stateCtx).textTheme.titleSmall),
          );
          Widget linha(List<Widget> filhos) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, f) in filhos.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: f),
              ],
            ],
          );

          return AlertDialog(
            title: Text(existente == null ? 'Novo cliente' : 'Editar cliente'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (erro != null)
                      Container(
                        key: const ValueKey('erro-cliente'),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: stateCtx.colors.dangerSoft,
                          borderRadius: AppRadius.md,
                        ),
                        child: Text(
                          erro!,
                          style: TextStyle(color: stateCtx.colors.danger),
                        ),
                      ),
                    secao('Identificação'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'pj',
                          label: Text('Empresa'),
                          icon: Icon(Icons.business_outlined),
                        ),
                        ButtonSegment(
                          value: 'pf',
                          label: Text('Pessoa'),
                          icon: Icon(Icons.person_outline),
                        ),
                      ],
                      selected: {tipo},
                      onSelectionChanged: (s) =>
                          setDialogState(() => tipo = s.first),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      label: tipo == 'pf' ? 'Nome' : 'Nome fantasia',
                      controller: nomeFantasia,
                    ),
                    if (tipo == 'pj') ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        label: 'Razão social (opcional)',
                        controller: razaoSocial,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        label: 'CNPJ (opcional)',
                        hint: '00.000.000/0000-00',
                        controller: cnpj,
                        keyboardType: TextInputType.number,
                      ),
                    ] else ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        label: 'CPF (opcional)',
                        hint: '000.000.000-00',
                        controller: cpf,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      label: 'Ramo de atividade (opcional)',
                      controller: ramo,
                    ),
                    secao('Contato'),
                    linha([
                      AppTextField(label: 'Telefone', controller: telefone),
                      AppTextField(label: 'Site', controller: site),
                    ]),
                    secao('Endereço'),
                    linha([
                      AppTextField(label: 'CEP', controller: cep),
                      AppTextField(label: 'Cidade', controller: cidade),
                      AppTextField(label: 'UF', controller: uf),
                    ]),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(label: 'Logradouro', controller: logradouro),
                    const SizedBox(height: AppSpacing.sm),
                    linha([
                      AppTextField(label: 'Número', controller: numero),
                      AppTextField(
                        label: 'Complemento',
                        controller: complemento,
                      ),
                      AppTextField(label: 'Bairro', controller: bairro),
                    ]),
                    secao('Observações'),
                    TextField(
                      controller: observacoes,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: salvando
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              PrimaryButton(
                label: existente == null ? 'Cadastrar' : 'Salvar',
                expand: false,
                isLoading: salvando,
                onPressed: salvando
                    ? null
                    : () async {
                        if (nomeFantasia.text.trim().isEmpty) {
                          setDialogState(
                            () => erro = 'Informe o nome do cliente.',
                          );
                          return;
                        }
                        final navigator = Navigator.of(dialogContext);
                        setDialogState(() {
                          salvando = true;
                          erro = null;
                        });
                        final falha = await controller.salvar(
                          id: existente?.id,
                          dados: DadosCliente(
                            nomeFantasia: nomeFantasia.text,
                            tipo: tipo,
                            // O documento do outro tipo não viaja: trocar de
                            // empresa para pessoa não pode deixar um CNPJ velho.
                            razaoSocial: tipo == 'pj' ? razaoSocial.text : '',
                            cnpj: tipo == 'pj' ? cnpj.text : '',
                            cpf: tipo == 'pf' ? cpf.text : '',
                            telefone: telefone.text,
                            site: site.text,
                            ramoAtividade: ramo.text,
                            observacoes: observacoes.text,
                            cep: cep.text,
                            logradouro: logradouro.text,
                            numero: numero.text,
                            complemento: complemento.text,
                            bairro: bairro.text,
                            cidade: cidade.text,
                            uf: uf.text,
                          ),
                        );
                        if (falha != null) {
                          if (stateCtx.mounted) {
                            setDialogState(() {
                              salvando = false;
                              erro = falha.message;
                            });
                          }
                          return;
                        }
                        navigator.pop();
                      },
              ),
            ],
          );
        },
      ),
    ),
  );
}
