import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../domain/versao_do_app.dart';

/// P11 — faixa que avisa que há versão nova do app Windows.
///
/// Até aqui o zip era trocado à mão e ninguém sabia que estava numa versão
/// velha até um bug já corrigido aparecer de novo. O aviso não bloqueia nada:
/// quem está no meio de um atendimento termina e atualiza depois.
///
/// Só existe no desktop — a web é sempre a versão do servidor — e consulta uma
/// vez por abertura: versão nova é assunto de dia, não de minuto.
final class AvisoVersao extends StatefulWidget {
  /// Injetável para teste; em produção lê o carimbo do build.
  final int build;

  /// Idem: a web nunca mostra, mas o teste roda na VM.
  final bool somenteDesktop;

  const AvisoVersao({
    super.key,
    this.build = buildLocal,
    this.somenteDesktop = true,
  });

  @override
  State<AvisoVersao> createState() => _AvisoVersaoState();
}

class _AvisoVersaoState extends State<AvisoVersao> {
  VersaoPublicada? _nova;
  bool _dispensado = false;

  @override
  void initState() {
    super.initState();
    if (widget.somenteDesktop && kIsWeb) return;
    if (widget.build <= 0) return;
    if (!GetIt.instance.isRegistered<ConsultarVersaoUsecase>()) return;
    unawaited(_consultar());
  }

  Future<void> _consultar() async {
    final res = await inject<ConsultarVersaoUsecase>()(
      const ConsultarVersaoParameters(),
    );
    if (!mounted) return;
    if (res case Success(:final value) when value.maisNovaQue(widget.build)) {
      setState(() => _nova = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nova = _nova;
    if (nova == null || _dispensado) return const SizedBox.shrink();
    final colors = context.colors;
    return Material(
      color: colors.infoSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.system_update_alt, color: colors.info),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                nova.notas.isEmpty
                    ? 'Há uma versão nova do aplicativo.'
                    : 'Há uma versão nova do aplicativo: ${nova.notas}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _dispensado = true),
              child: const Text('Depois'),
            ),
            FilledButton(
              onPressed: () => launchUrl(
                Uri.parse(nova.urlDownload),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Baixar'),
            ),
          ],
        ),
      ),
    );
  }
}
