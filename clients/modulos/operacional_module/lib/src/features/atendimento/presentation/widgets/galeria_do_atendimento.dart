import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/midia_mensagem.dart';
import '../../domain/parameters/presenca_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';

/// P3 — os arquivos trocados na conversa, em grade, com visualização ampliada.
///
/// As URLs vêm assinadas com TTL curto: a grade é para ver agora. Por isso a
/// tela recarrega ao abrir em vez de guardar a lista de uma sessão anterior.
class GaleriaDoAtendimento extends StatefulWidget {
  final int atendimentoId;

  const GaleriaDoAtendimento({super.key, required this.atendimentoId});

  /// Abre a galeria como diálogo — é o caminho da conversa embutida no quadro,
  /// onde empurrar uma rota nova tiraria o atendente do quadro inteiro.
  static Future<void> abrir(BuildContext context, int atendimentoId) =>
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 720,
            height: 520,
            child: GaleriaDoAtendimento(atendimentoId: atendimentoId),
          ),
        ),
      );

  @override
  State<GaleriaDoAtendimento> createState() => _GaleriaDoAtendimentoState();
}

class _GaleriaDoAtendimentoState extends State<GaleriaDoAtendimento> {
  late Future<ReturnSuccessOrError<List<MidiaMensagem>, MidiasError>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _carregar();
  }

  Future<ReturnSuccessOrError<List<MidiaMensagem>, MidiasError>> _carregar() async {
    final usecase = inject<ListarMidiasUsecase>();
    return await usecase(
      ListarMidiasParameters(atendimentoId: widget.atendimentoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.perm_media_outlined, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Arquivos da conversa',
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
              FutureBuilder<ReturnSuccessOrError<List<MidiaMensagem>, MidiasError>>(
                future: _futuro,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return switch (snapshot.data!) {
                    Failure(:final error) => AppErrorView(
                      message: error.message,
                      onRetry: () => setState(() => _futuro = _carregar()),
                    ),
                    Success(:final value) when value.isEmpty =>
                      const AppEmptyView(
                        icon: Icons.perm_media_outlined,
                        title: 'Nenhum arquivo ainda',
                        subtitle: 'Fotos, áudios e documentos aparecem aqui.',
                      ),
                    Success(:final value) => GridView.builder(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 160,
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisSpacing: AppSpacing.sm,
                          ),
                      itemCount: value.length,
                      itemBuilder: (context, i) =>
                          _Celula(midia: value[i]),
                    ),
                  };
                },
              ),
        ),
      ],
    );
  }
}

class _Celula extends StatelessWidget {
  final MidiaMensagem midia;

  const _Celula({required this.midia});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ehImagem = midia.tipo == TipoMidia.imagem;
    return InkWell(
      onTap: ehImagem ? () => _ampliar(context) : null,
      child: Container(
        decoration: BoxDecoration(
          color: colors.chip,
          borderRadius: AppRadius.card,
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ehImagem
            ? Image.network(
                midia.urlAssinada,
                fit: BoxFit.cover,
                // A URL expira: em vez de um ícone quebrado, diz o que houve.
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.image_not_supported_outlined),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_icone(midia.tipo), size: 28),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Text(
                      midia.nomeArquivo,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static IconData _icone(TipoMidia tipo) => switch (tipo) {
    TipoMidia.imagem => Icons.image_outlined,
    TipoMidia.audio => Icons.graphic_eq,
    TipoMidia.video => Icons.videocam_outlined,
    TipoMidia.documento => Icons.description_outlined,
  };

  void _ampliar(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.network(midia.urlAssinada)),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
