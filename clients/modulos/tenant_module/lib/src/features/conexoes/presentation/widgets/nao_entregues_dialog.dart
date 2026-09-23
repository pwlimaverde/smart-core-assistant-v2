import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/permissoes.dart';
import '../../domain/errors/conexoes_errors.dart';
import '../../domain/model/conexao.dart';
import '../../domain/parameters/conexoes_parameters.dart';
import '../../domain/usecases/conexoes_usecases.dart';

/// P9 — as mensagens que o atendente mandou e que não chegaram.
///
/// Mora na tela de conexões porque a causa é de conexão: o contato estava sem
/// sessão ativa na hora do envio. Reenviar só adianta depois que a conexão
/// voltar — e a caixa diz isso quando é o caso.
Future<void> mostrarNaoEntregues(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      child: SizedBox(width: 560, height: 480, child: _NaoEntregues()),
    ),
  );
}

class _NaoEntregues extends StatefulWidget {
  const _NaoEntregues();

  @override
  State<_NaoEntregues> createState() => _NaoEntreguesState();
}

class _NaoEntreguesState extends State<_NaoEntregues> {
  late Future<ReturnSuccessOrError<List<MensagemParada>, ConexoesError>>
  _futuro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    _futuro = inject<ListarNaoEntreguesUsecase>()(noParams);
  }

  Future<void> _reenviar(MensagemParada m) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await inject<ReenviarNaoEntregueUsecase>()(
      ConexaoIdParameters(id: m.id),
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (res) {
          Success(:final value) => value.texto,
          Failure(:final error) => error.message,
        }),
      ),
    );
    setState(_carregar);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    final podeReenviar = sessaoPodeAlterar('/tenant/conexoes');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.report_gmailerrorred_outlined, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Mensagens não entregues',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              FutureBuilder<
                ReturnSuccessOrError<List<MensagemParada>, ConexoesError>
              >(
                future: _futuro,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return switch (snapshot.data!) {
                    Failure(:final error) => AppErrorView(
                      message: error.message,
                    ),
                    Success(:final value) when value.isEmpty =>
                      const AppEmptyView(
                        icon: Icons.mark_email_read_outlined,
                        title: 'Nada parado',
                        subtitle: 'Todas as mensagens encontraram destino.',
                      ),
                    Success(:final value) => ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: value.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = value[i];
                        return ListTile(
                          title: Text(
                            m.contato.isEmpty ? 'Contato sem nome' : m.contato,
                          ),
                          subtitle: Text(
                            '${m.trecho}\n${m.motivo}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: muted),
                          ),
                          isThreeLine: true,
                          trailing: podeReenviar
                              ? TextButton.icon(
                                  icon: const Icon(Icons.send, size: 16),
                                  label: const Text('Reenviar'),
                                  onPressed: () => _reenviar(m),
                                )
                              : null,
                        );
                      },
                    ),
                  };
                },
              ),
        ),
      ],
    );
  }
}
