import 'package:dependencies_module/dependencies_module.dart';

import '../../../treinamento/presentation/controllers/treinamento_controllers.dart';
import '../../../treinamento/presentation/widgets/dialogo_treinamento.dart';
import '../../domain/errors/ensaio_errors.dart';
import '../../domain/model/ensaio.dart';
import '../../domain/parameters/ensaio_parameters.dart';
import '../../domain/usecases/ensaio_usecases.dart';

/// P17 — as avaliações do teste de resposta, para virar material.
///
/// A aba "Testar" colhe a correção ("a resposta certa seria…"); até aqui ela
/// ficava guardada sem caminho de volta. Aqui a correção vira treinamento pela
/// criação de sempre — revisar, finalizar, vetorizar — e sai da lista.
class AbaAvaliacoes extends StatefulWidget {
  /// Quem pode treinar; sem isso a aba só mostra.
  final bool podeAlterar;

  const AbaAvaliacoes({super.key, this.podeAlterar = true});

  @override
  State<AbaAvaliacoes> createState() => _AbaAvaliacoesState();
}

class _AbaAvaliacoesState extends State<AbaAvaliacoes> {
  late Future<ReturnSuccessOrError<List<AvaliacaoPendente>, EnsaioError>>
  _futuro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    // Sem o usecase registrado (testes de tela da página), a aba fica vazia
    // em vez de derrubar a página inteira.
    _futuro = GetIt.instance.isRegistered<ListarAvaliacoesUsecase>()
        ? inject<ListarAvaliacoesUsecase>()(noParams)
        : Future.value(const Success(<AvaliacaoPendente>[]));
  }

  Future<void> _tratar(AvaliacaoPendente a, {required bool virou}) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await inject<TratarAvaliacaoUsecase>()(
      TratarAvaliacaoParameters(id: a.id, virouTreinamento: virou),
    );
    if (!mounted) return;
    if (res case Failure(:final error)) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    setState(_carregar);
  }

  Future<void> _virarTreinamento(AvaliacaoPendente a) async {
    final criou = await abrirCriacao(
      context,
      inject<TreinamentoController>(),
      conteudoInicial: a.conteudoParaTreinamento,
    );
    // Só sai da lista depois de virar material: cancelar a caixa não pode
    // perder a correção.
    if (criou) await _tratar(a, virou: true);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    return FutureBuilder<
      ReturnSuccessOrError<List<AvaliacaoPendente>, EnsaioError>
    >(
      future: _futuro,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return switch (snapshot.data!) {
          Failure(:final error) => AppErrorView(
            message: error.message,
            onRetry: () => setState(_carregar),
          ),
          Success(:final value) when value.isEmpty => const AppEmptyView(
            icon: Icons.fact_check_outlined,
            title: 'Nada para revisar',
            subtitle:
                'As avaliações feitas na aba Testar aparecem aqui até virarem '
                'material ou serem dispensadas.',
          ),
          Success(:final value) => ListView.separated(
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = value[i];
              return ListTile(
                leading: Icon(
                  a.boa ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
                  color: a.boa ? null : Theme.of(context).colorScheme.error,
                ),
                title: Text(a.pergunta),
                subtitle: Text(
                  a.respostaCorrigida.isEmpty
                      ? 'IA: ${a.respostaBot}'
                      : 'Correção: ${a.respostaCorrigida}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: muted),
                ),
                isThreeLine: true,
                trailing: widget.podeAlterar
                    ? Wrap(
                        spacing: 4,
                        children: [
                          if (a.podeVirarTreinamento)
                            TextButton(
                              onPressed: () => _virarTreinamento(a),
                              child: const Text('Virar treinamento'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Dispensar',
                            onPressed: () => _tratar(a, virou: false),
                          ),
                        ],
                      )
                    : null,
              );
            },
          ),
        };
      },
    );
  }
}
