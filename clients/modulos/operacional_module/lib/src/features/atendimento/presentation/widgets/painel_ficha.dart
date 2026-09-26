import 'package:dependencies_module/dependencies_module.dart' show GetIt;
import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:intl/intl.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/evento_timeline.dart';
import '../../domain/model/ficha.dart';
import '../../domain/model/midia_mensagem.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/parameters/presenca_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/ficha_controller.dart';
import '../escrita_no_quadro.dart';
import 'atendimento_card_content.dart';
import 'atendimento_no_quadro.dart';
import 'avatar_do_contato.dart';
import 'dialogo_valor_campo.dart';
import 'galeria_do_atendimento.dart';

/// Cor a partir do hex do catálogo. Hex inválido cai no padrão em vez de
/// derrubar o painel — uma cor errada não justifica perder a ficha inteira.
Color corDaEtiqueta(String hex) {
  final limpo = hex.replaceFirst('#', '');
  final valor = int.tryParse(limpo, radix: 16);
  if (valor == null || limpo.length != 6) return const Color(0xFFA98F71);
  return Color(0xFF000000 | valor);
}

/// O painel de informações do atendimento, à direita da conversa — o
/// `ws-info` do workspace.
///
/// Abre junto com a conversa, no primeiro clique no cartão: tudo o que se
/// manipula num atendimento está aqui, sem botão extra no cartão. De cima para
/// baixo: quem é o contato, o estado do atendimento (status, prioridade, dono,
/// quadro), a resposta automática, as etiquetas, os campos personalizados, o
/// que a IA encontrou do contato, os arquivos trocados, a história e as
/// anotações internas.
class PainelFicha extends StatelessWidget {
  final FichaController controller;

  /// Largura do painel. `null` ocupa o espaço que quem o embute der — a
  /// metade do painel da conversa; como gaveta, o que couber.
  final double? largura;

  /// Quando vem, o painel ganha o botão de fechar no canto do cabeçalho.
  final VoidCallback? aoFechar;

  /// O cartão e as ações do quadro. Falta quando a conversa foi aberta fora
  /// do quadro (celular, janela estreita): aí o painel mostra só a ficha.
  final AtendimentoNoQuadro? noQuadro;

  /// Quem é o contato, para o cabeçalho quando não há cartão.
  final String nomeDoContato;
  final String telefoneDoContato;
  final String fotoDoContato;

  const PainelFicha({
    required this.controller,
    this.largura = 320,
    this.aoFechar,
    this.noQuadro,
    this.nomeDoContato = '',
    this.telefoneDoContato = '',
    this.fotoDoContato = '',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: largura,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: BlocBuilder<FichaController, ViewState<FichaAtendimento>>(
        bloc: controller,
        builder: (context, state) => switch (state) {
          InitialState() ||
          LoadingState() => const Center(child: CircularProgressIndicator()),
          // A ficha falha sozinha: a conversa ao lado continua utilizável, e
          // a mensagem precisa dizer que o que caiu foi o painel.
          ErrorState(:final error) => AppErrorView(
            message: error.message,
            onRetry: () => controller.abrir(controller.atendimentoId),
          ),
          SuccessState(:final data) => _Conteudo(
            ficha: data,
            controller: controller,
            painel: this,
          ),
        },
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  final FichaAtendimento ficha;
  final FichaController controller;
  final PainelFicha painel;

  const _Conteudo({
    required this.ficha,
    required this.controller,
    required this.painel,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    final noQuadro = painel.noQuadro;
    final estilo = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: muted, fontSize: 12);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Cabecalho(painel: painel, controller: controller),
        if (noQuadro != null) _SecaoDoAtendimento(noQuadro: noQuadro),
        // D3 — o interruptor da IA vem antes do resto da ficha: é o estado
        // mais consequente da conversa, e é o que alguém vem procurar aqui
        // quando o bot parou de responder só nesta thread.
        _Secao(
          titulo: 'Resposta automática',
          child: _BotDaConversa(ficha: ficha, controller: controller),
        ),
        _Secao(
          titulo: 'Etiquetas',
          acao: IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'Nova etiqueta',
            visualDensity: VisualDensity.compact,
            onPressed: () => _abrirCriacaoEtiqueta(context, controller),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ficha.aplicadas.isEmpty)
                Text('Nenhuma etiqueta nesta conversa.', style: estilo)
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final etiqueta in ficha.aplicadas)
                      _Chip(
                        etiqueta: etiqueta,
                        // Tirar a etiqueta é a ação de quem já a colou;
                        // oferecer o X direto evita um menu para desfazer um
                        // clique.
                        aoRemover: () => _alternar(
                          context,
                          controller,
                          etiqueta.id,
                          aplicar: false,
                        ),
                      ),
                  ],
                ),
              if (ficha.disponiveis.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Colar nesta conversa',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final etiqueta in ficha.disponiveis)
                      _EtiquetaParaColar(
                        etiqueta: etiqueta,
                        aoColar: () => _alternar(
                          context,
                          controller,
                          etiqueta.id,
                          aplicar: true,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // N9 E13 — os campos que o tenant desenhou para o cartão: o conteúdo
        // da conversa (número do pedido, data de retorno). Clicar edita.
        if (ficha.campos.isNotEmpty)
          _Secao(
            titulo: 'Campos personalizados',
            child: Column(
              children: [
                for (final campo in ficha.campos)
                  _LinhaDeCampo(campo: campo, controller: controller),
              ],
            ),
          ),
        // P15 — o que a IA encontrou do contato nas conversas e não tem coluna
        // no cadastro. Só de leitura: é pista, não cadastro.
        if (ficha.dadosDoContato.isNotEmpty)
          _Secao(
            titulo: 'Dados do contato',
            dica: 'Dados que a IA encontrou nas conversas.',
            child: Column(
              children: [
                for (final entrada in ficha.dadosDoContato.entries)
                  CampoDoPainel(chave: entrada.key, valor: entrada.value),
              ],
            ),
          ),
        if (GetIt.instance.isRegistered<ListarMidiasUsecase>())
          _SecaoDeMidia(atendimentoId: controller.atendimentoId),
        _Secao(
          titulo: 'Anotações',
          dica: 'Internas: o contato nunca as vê.',
          acao: IconButton(
            icon: const Icon(Icons.note_add_outlined, size: 16),
            tooltip: 'Anotar',
            visualDensity: VisualDensity.compact,
            onPressed: () => _abrirNota(context, controller),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ficha.notas.isEmpty)
                Text('Nada anotado ainda.', style: estilo)
              else
                for (final nota in ficha.notas) ...[
                  _Nota(nota: nota, controller: controller),
                  const SizedBox(height: 6),
                ],
            ],
          ),
        ),
        _Secao(
          titulo: 'História',
          acao: IconButton(
            icon: const Icon(Icons.history, size: 16),
            tooltip: 'Ver a história do atendimento',
            visualDensity: VisualDensity.compact,
            onPressed: () => _abrirTimeline(context, controller.atendimentoId),
          ),
          child: Text(
            'Aberto, movido, anotado, etiquetado e encerrado — com quem e '
            'quando.',
            style: estilo,
          ),
        ),
      ],
    );
  }
}

/// O topo do painel: avatar grande, nome, telefone e os atalhos.
class _Cabecalho extends StatelessWidget {
  final PainelFicha painel;
  final FichaController controller;

  const _Cabecalho({required this.painel, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resumo = painel.noQuadro?.resumo;
    final nome =
        resumo?.nomeParaExibir ??
        (painel.nomeDoContato.isNotEmpty
            ? painel.nomeDoContato
            : 'Atendimento #${controller.atendimentoId}');
    final telefone = resumo?.contatoTelefone ?? painel.telefoneDoContato;
    final foto = resumo?.contatoFotoUrl ?? painel.fotoDoContato;
    final fechar = painel.aoFechar;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AvatarDoContato(nome: nome, fotoUrl: foto, raio: 38),
              ),
              const SizedBox(height: 12),
              Text(
                nome,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: colors.fgStrong,
                ),
              ),
              if (telefone.isNotEmpty && telefone != nome) ...[
                const SizedBox(height: 3),
                Text(
                  telefone,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.fgMuted),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (GetIt.instance.isRegistered<ListarMidiasUsecase>())
                    _BotaoRedondo(
                      icone: Icons.perm_media_outlined,
                      dica: 'Arquivos da conversa',
                      aoTocar: () => GaleriaDoAtendimento.abrir(
                        context,
                        controller.atendimentoId,
                      ),
                    ),
                  _BotaoRedondo(
                    icone: Icons.history,
                    dica: 'História do atendimento',
                    aoTocar: () =>
                        _abrirTimeline(context, controller.atendimentoId),
                  ),
                  _BotaoRedondo(
                    icone: Icons.sticky_note_2_outlined,
                    dica: 'Nova anotação',
                    aoTocar: () => _abrirNota(context, controller),
                  ),
                ],
              ),
            ],
          ),
          if (fechar != null)
            Positioned(
              top: -12,
              right: -12,
              child: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Fechar os detalhes (Esc)',
                onPressed: fechar,
              ),
            ),
        ],
      ),
    );
  }
}

class _BotaoRedondo extends StatelessWidget {
  final IconData icone;
  final String dica;
  final VoidCallback aoTocar;

  const _BotaoRedondo({
    required this.icone,
    required this.dica,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: dica,
        child: Material(
          color: colors.chip,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: aoTocar,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icone, size: 16, color: colors.accentHover),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma seção do painel (`ws-info__sec`): título miúdo em caixa alta, uma ação
/// opcional à direita e o conteúdo.
class _Secao extends StatelessWidget {
  final String titulo;
  final String? dica;
  final Widget? acao;
  final Widget child;

  const _Secao({
    required this.titulo,
    required this.child,
    this.dica,
    this.acao,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    titulo.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: colors.fgMuted,
                    ),
                  ),
                ),
                ?acao,
              ],
            ),
          ),
          if (dica case final texto?) ...[
            Text(texto, style: TextStyle(fontSize: 11, color: colors.fgSubtle)),
            const SizedBox(height: 6),
          ],
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    );
  }
}

/// Uma linha chave/valor do painel (`ws-info__field`).
class CampoDoPainel extends StatelessWidget {
  final String chave;
  final String valor;
  final Widget? trailing;

  const CampoDoPainel({
    super.key,
    required this.chave,
    required this.valor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chave, style: TextStyle(fontSize: 12, color: colors.fgMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.fgStrong,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// O estado do atendimento, editável ali mesmo: status, prioridade, dono e
/// quadro. É o que o menu do cartão fazia, agora à vista.
class _SecaoDoAtendimento extends StatelessWidget {
  final AtendimentoNoQuadro noQuadro;

  const _SecaoDoAtendimento({required this.noQuadro});

  Future<void> _rodar(
    BuildContext context,
    Future<String?> Function() acao,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = await acao();
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final a = noQuadro.resumo;
    final escreve = quadroPodeEscrever();
    final fluxo = noQuadro.fluxoRotulo;

    return _Secao(
      titulo: 'Atendimento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LinhaComMenu<String>(
            chave: 'Status',
            valor: rotuloDoStatus(a.status),
            dica: 'Mudar o status',
            habilitado: escreve,
            opcoes: [
              for (final entrada in rotulosDeStatus.entries)
                // Arquivar é curadoria do histórico, não do atendimento.
                if (entrada.key != a.status && entrada.key != 'arquivado')
                  (entrada.key, entrada.value),
            ],
            aoEscolher: (s) => _rodar(context, () => noQuadro.definirStatus(s)),
          ),
          _LinhaComMenu<String>(
            chave: 'Prioridade',
            valorWidget: TagDePrioridade(prioridade: a.prioridade),
            dica: 'Mudar a prioridade',
            habilitado: escreve,
            opcoes: [
              for (final (valor, rotulo) in prioridadesOferecidas)
                if (valor != a.prioridade) (valor, rotulo),
            ],
            aoEscolher: (p) =>
                _rodar(context, () => noQuadro.definirPrioridade(p)),
          ),
          CampoDoPainel(
            chave: 'Atendente',
            valor: a.atendenteNome.isNotEmpty
                ? a.atendenteNome
                : (a.atendenteHumanoId != null ? 'Atribuído' : 'Sem atendente'),
          ),
          if (noQuadro.etapaNome.isNotEmpty)
            CampoDoPainel(chave: 'Etapa', valor: noQuadro.etapaNome),
          if (fluxo.isNotEmpty) CampoDoPainel(chave: 'Quadro', valor: fluxo),
          CampoDoPainel(
            chave: 'Aberto em',
            valor: DateFormat('dd/MM/yyyy HH:mm').format(a.dataInicio),
          ),
          if (escreve) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (a.atendenteHumanoId == null)
                  BotaoDeAcao(
                    rotulo: 'Assumir',
                    icone: Icons.person_add_alt_1_outlined,
                    tom: TomDaAcao.ouro,
                    aoTocar: () =>
                        _rodar(context, () => noQuadro.assumir(true)),
                  )
                else
                  BotaoDeAcao(
                    rotulo: 'Devolver à fila',
                    icone: Icons.undo,
                    aoTocar: () =>
                        _rodar(context, () => noQuadro.assumir(false)),
                  ),
                if (a.revisaoPendente)
                  BotaoDeAcao(
                    rotulo: 'Marcar como revisada',
                    icone: Icons.rate_review_outlined,
                    tom: TomDaAcao.sucesso,
                    aoTocar: () => _rodar(context, noQuadro.marcarRevisado),
                  ),
              ],
            ),
          ],
          if (a.revisaoPendente && !escreve)
            Text(
              'A IA respondeu com pouca confiança.',
              style: TextStyle(fontSize: 11, color: colors.warning),
            ),
        ],
      ),
    );
  }
}

/// Uma linha chave/valor em que o valor abre um menu de opções.
class _LinhaComMenu<T> extends StatelessWidget {
  final String chave;
  final String? valor;
  final Widget? valorWidget;
  final String dica;
  final bool habilitado;
  final List<(T, String)> opcoes;
  final void Function(T) aoEscolher;

  const _LinhaComMenu({
    required this.chave,
    required this.dica,
    required this.habilitado,
    required this.opcoes,
    required this.aoEscolher,
    this.valor,
    this.valorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mostrado =
        valorWidget ??
        Text(
          valor ?? '',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.fgStrong,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(chave, style: TextStyle(fontSize: 12, color: colors.fgMuted)),
          const Spacer(),
          if (!habilitado || opcoes.isEmpty)
            Padding(padding: const EdgeInsets.all(4), child: mostrado)
          else
            PopupMenuButton<T>(
              tooltip: dica,
              onSelected: aoEscolher,
              itemBuilder: (_) => [
                for (final (v, rotulo) in opcoes)
                  PopupMenuItem(value: v, child: Text(rotulo)),
              ],
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mostrado,
                    Icon(Icons.expand_more, size: 16, color: colors.fgMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// O tom de um botão de ação do workspace (`ws-qa`).
enum TomDaAcao { neutro, ouro, sucesso, perigo }

/// Botão de ação do workspace — a faixa de ações rápidas da conversa e as
/// ações do painel de informações.
class BotaoDeAcao extends StatelessWidget {
  final String rotulo;
  final IconData icone;
  final TomDaAcao tom;
  final VoidCallback? aoTocar;

  const BotaoDeAcao({
    super.key,
    required this.rotulo,
    required this.icone,
    required this.aoTocar,
    this.tom = TomDaAcao.neutro,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fundo, cor, borda) = switch (tom) {
      TomDaAcao.ouro => (
        colors.accentSoft,
        colors.accentHover,
        colors.accent.withValues(alpha: 0.3),
      ),
      TomDaAcao.sucesso => (
        colors.successSoft,
        colors.success,
        colors.success.withValues(alpha: 0.3),
      ),
      TomDaAcao.perigo => (
        colors.dangerSoft,
        colors.danger,
        colors.danger.withValues(alpha: 0.25),
      ),
      TomDaAcao.neutro => (colors.chip, colors.fg, colors.border),
    };
    return Material(
      color: fundo,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.md,
        side: BorderSide(color: borda),
      ),
      child: InkWell(
        borderRadius: AppRadius.md,
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 13, color: cor),
              const SizedBox(width: 6),
              Text(
                rotulo,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Os arquivos da conversa em miniatura (`MÍDIA & ARQUIVOS`), com o "ver
/// tudo" que abre a galeria.
class _SecaoDeMidia extends StatefulWidget {
  final int atendimentoId;

  const _SecaoDeMidia({required this.atendimentoId});

  @override
  State<_SecaoDeMidia> createState() => _SecaoDeMidiaState();
}

class _SecaoDeMidiaState extends State<_SecaoDeMidia> {
  late final Future<ReturnSuccessOrError<List<MidiaMensagem>, MidiasError>>
  _futuro = inject<ListarMidiasUsecase>()(
    ListarMidiasParameters(atendimentoId: widget.atendimentoId),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _Secao(
      titulo: 'Mídia & arquivos',
      acao: TextButton(
        onPressed: () =>
            GaleriaDoAtendimento.abrir(context, widget.atendimentoId),
        child: const Text('ver tudo', style: TextStyle(fontSize: 11)),
      ),
      child:
          FutureBuilder<ReturnSuccessOrError<List<MidiaMensagem>, MidiasError>>(
            future: _futuro,
            builder: (context, snapshot) {
              final midias = switch (snapshot.data) {
                Success(:final value) => value,
                _ => const <MidiaMensagem>[],
              };
              if (midias.isEmpty) {
                return Text(
                  snapshot.hasData
                      ? 'Nenhum arquivo nesta conversa.'
                      : 'Carregando…',
                  style: TextStyle(fontSize: 12, color: colors.fgMuted),
                );
              }
              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final m in midias.take(6))
                    InkWell(
                      onTap: () => GaleriaDoAtendimento.abrir(
                        context,
                        widget.atendimentoId,
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadius.sm,
                        child: m.tipo == TipoMidia.imagem
                            ? Image.network(
                                m.urlAssinada,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _MiniaturaSemImagem(midia: m),
                              )
                            : _MiniaturaSemImagem(midia: m),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}

class _MiniaturaSemImagem extends StatelessWidget {
  final MidiaMensagem midia;

  const _MiniaturaSemImagem({required this.midia});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icone = switch (midia.tipo) {
      TipoMidia.audio => Icons.graphic_eq,
      TipoMidia.video => Icons.movie_outlined,
      TipoMidia.imagem => Icons.image_outlined,
      TipoMidia.documento => Icons.description_outlined,
    };
    return Container(
      color: colors.chip,
      alignment: Alignment.center,
      child: Icon(icone, color: colors.accentHover),
    );
  }
}

class _Nota extends StatelessWidget {
  final Nota nota;
  final FichaController controller;

  const _Nota({required this.nota, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 8),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        borderRadius: AppRadius.md,
        border: Border(left: BorderSide(color: colors.warning, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _quando(nota.criadoEm),
                  style: TextStyle(fontSize: 10.5, color: colors.fgMuted),
                ),
              ),
              // P5 — nota escrita errada ficava para sempre.
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Excluir anotação',
                visualDensity: VisualDensity.compact,
                onPressed: () => _excluirNota(context, controller, nota.id),
              ),
            ],
          ),
          Text(
            nota.texto,
            style: TextStyle(fontSize: 12.5, color: colors.fgStrong),
          ),
        ],
      ),
    );
  }
}

/// Quando a nota foi escrita, em linguagem de quem lê.
String _quando(DateTime quando) {
  final minutos = DateTime.now().difference(quando).inMinutes;
  if (minutos < 1) return 'agora';
  if (minutos < 60) return 'há $minutos min';
  final horas = minutos ~/ 60;
  if (horas < 24) return 'há ${horas}h';
  final dias = horas ~/ 24;
  return dias == 1 ? 'ontem' : 'há $dias dias';
}

/// D3 — o interruptor da IA nesta conversa.
///
/// Assumir o atendimento desliga o bot automaticamente, e por muito tempo nada
/// devolvia o valor: a conversa que passou por um humano ficava sem IA para
/// sempre, sem tela para reverter. Este é o caminho de volta.
///
/// A tranca do `desatribuir` continua de pé no servidor — devolver o cartão
/// não religa sozinho. O que existe agora é uma ação deliberada.
class _BotDaConversa extends StatelessWidget {
  final FichaAtendimento ficha;
  final FichaController controller;

  const _BotDaConversa({required this.ficha, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ligado = ficha.botPodeAtender;
    final colors = context.colors;

    return Row(
      children: [
        Icon(
          ligado ? Icons.smart_toy_outlined : Icons.smart_toy,
          size: 18,
          color: ligado ? colors.accent : colors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            ligado
                ? 'A IA responde nesta conversa.'
                : 'A IA está calada nesta conversa.',
            style: TextStyle(
              fontSize: 12,
              color: ligado ? colors.fg : colors.warning,
            ),
          ),
        ),
        Switch(
          value: ligado,
          onChanged: (v) => _definirBot(context, controller, v),
        ),
      ],
    );
  }
}

/// Abre o diálogo de anotação — a ação rápida "Nota" da conversa.
Future<void> abrirDialogoDeNota(
  BuildContext context,
  FichaController controller,
) => _abrirNota(context, controller);

/// Abre o diálogo de etiqueta nova — a ação rápida "Etiqueta" da conversa.
Future<void> abrirDialogoDeEtiqueta(
  BuildContext context,
  FichaController controller,
) => _abrirCriacaoEtiqueta(context, controller);

/// Cola ou tira uma etiqueta — a ação rápida "Etiqueta" da conversa.
Future<void> alternarEtiqueta(
  BuildContext context,
  FichaController controller,
  int etiquetaId, {
  required bool aplicar,
}) => _alternar(context, controller, etiquetaId, aplicar: aplicar);

/// Sem diálogo de confirmação, ao contrário do interruptor da conexão.
///
/// Lá o desligamento cala um número inteiro e quem esbarrou no controle não
/// descobriria pelo silêncio. Aqui o efeito é de uma conversa só, está à vista
/// de quem a está lendo, e é reversível no mesmo clique — pedir confirmação
/// seria atrito numa ação que o atendente toma o tempo todo.
Future<void> _definirBot(
  BuildContext context,
  FichaController controller,
  bool habilitado,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final erro = await controller.definirBot(habilitado);
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro.message)));
  }
}

Future<void> _alternar(
  BuildContext context,
  FichaController controller,
  int etiquetaId, {
  required bool aplicar,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final erro = await controller.alternar(
    etiquetaId: etiquetaId,
    aplicar: aplicar,
  );
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro.message)));
  }
}

/// Cores oferecidas para etiqueta nova.
///
/// Lista fechada, como as colunas do quadro: a cor serve para distinguir de
/// relance, e uma paleta repetida entre tenants faz isso melhor que um
/// arco-íris escolhido a dedo.
const coresDeEtiqueta = <String>[
  '#a98f71',
  '#ef4444',
  '#f59e0b',
  '#10b981',
  '#3b82f6',
  '#8b5cf6',
];

Future<void> _abrirCriacaoEtiqueta(
  BuildContext context,
  FichaController controller,
) async {
  final nome = TextEditingController();
  var cor = coresDeEtiqueta.first;
  String? erro;
  var salvando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: const Text('Nova etiqueta'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Nome',
                  hint: 'ex: aguardando pagamento',
                  controller: nome,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final opcao in coresDeEtiqueta)
                      InkWell(
                        onTap: () => setStateDialog(() => cor = opcao),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: corDaEtiqueta(opcao),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: opcao == cor
                                  ? Theme.of(stateCtx).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (erro case final msg?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    msg,
                    style: TextStyle(
                      color: Theme.of(stateCtx).colorScheme.error,
                    ),
                  ),
                ],
              ],
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
              label: 'Criar',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      if (nome.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o nome da etiqueta.',
                        );
                        return;
                      }
                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });
                      final falha = await controller.criarEtiqueta(
                        nome: nome.text.trim(),
                        cor: cor,
                      );
                      if (falha != null) {
                        if (stateCtx.mounted) {
                          setStateDialog(() {
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
        ),
      ),
    ),
  );
}

Future<void> _abrirNota(
  BuildContext context,
  FichaController controller,
) async {
  final texto = TextEditingController();
  String? erro;
  var salvando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [texto],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: const Text('Anotar'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: texto,
                  maxLines: 6,
                  minLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'O que registrar',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    helperText: 'Só a equipe vê. O contato, nunca.',
                  ),
                ),
                if (erro case final msg?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    msg,
                    style: TextStyle(
                      color: Theme.of(stateCtx).colorScheme.error,
                    ),
                  ),
                ],
              ],
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
              label: 'Salvar',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      if (texto.text.trim().isEmpty) {
                        setStateDialog(() => erro = 'Escreva a anotação.');
                        return;
                      }
                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });
                      final falha = await controller.anotar(texto.text.trim());
                      if (falha != null) {
                        if (stateCtx.mounted) {
                          setStateDialog(() {
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
        ),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  final Etiqueta etiqueta;
  final VoidCallback aoRemover;

  const _Chip({required this.etiqueta, required this.aoRemover});

  @override
  Widget build(BuildContext context) {
    final cor = corDaEtiqueta(etiqueta.cor);
    final rotulo = Text(
      etiqueta.nome,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color.lerp(cor, Colors.black, 0.25),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 2, 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(color: cor.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: cor),
          const SizedBox(width: 5),
          // P14 — a etiqueta que a IA colocou se distingue da que uma pessoa
          // pôs. Tirá-la impede a IA de recolocar nesta conversa.
          if (etiqueta.aplicadaPelaIa)
            Tooltip(
              message:
                  'Aplicada pela IA. Se tirar, ela não volta nesta conversa.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  rotulo,
                  const SizedBox(width: 3),
                  Icon(Icons.auto_awesome, size: 11, color: cor),
                ],
              ),
            )
          else
            rotulo,
          InkWell(
            customBorder: const CircleBorder(),
            onTap: aoRemover,
            child: Tooltip(
              message: 'Tirar desta conversa',
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: context.colors.fgMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta do catálogo que ainda não está na conversa: um toque a cola.
class _EtiquetaParaColar extends StatelessWidget {
  final Etiqueta etiqueta;
  final VoidCallback aoColar;

  const _EtiquetaParaColar({required this.etiqueta, required this.aoColar});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cor = corDaEtiqueta(etiqueta.cor);
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.pill,
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: aoColar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 11, color: cor),
              const SizedBox(width: 3),
              Text(
                etiqueta.nome,
                style: TextStyle(fontSize: 11, color: colors.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um campo do cartão no painel: nome à esquerda, valor à direita, e o toque
/// que abre a edição.
class _LinhaDeCampo extends StatelessWidget {
  final ValorCampo campo;
  final FichaController controller;

  const _LinhaDeCampo({required this.campo, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      borderRadius: AppRadius.sm,
      onTap: () => abrirEdicaoDeValor(context, campo, controller),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                campo.nome,
                style: TextStyle(fontSize: 12, color: colors.fgMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (campo.obrigatorio && !campo.preenchido) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Campo obrigatório',
                child: Icon(
                  Icons.error_outline,
                  size: 13,
                  color: colors.warning,
                ),
              ),
            ],
            // De onde veio o valor muda o quanto se confia nele: um número
            // que a IA deduziu de "acho que foi o 12345" merece um olhar
            // antes de virar decisão.
            if (campo.veioDaIa && campo.preenchido) ...[
              const SizedBox(width: 4),
              Tooltip(
                message:
                    'Preenchido pela IA '
                    '(confiança ${(campo.confianca * 100).round()}%)',
                child: Icon(Icons.auto_awesome, size: 13, color: colors.accent),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                campo.preenchido ? _legivel(campo) : 'Não informado',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: campo.preenchido
                      ? FontWeight.w500
                      : FontWeight.normal,
                  color: campo.preenchido ? colors.fgStrong : colors.fgSubtle,
                  fontStyle: campo.preenchido
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined, size: 14, color: colors.fgSubtle),
          ],
        ),
      ),
    );
  }

  /// O valor como gente lê.
  ///
  /// O JSON cru serve à máquina: `"cartao"` com aspas, `true` em inglês, e o
  /// id de uma opção em vez do rótulo que a pessoa escolheu.
  String _legivel(ValorCampo c) {
    final bruto = c.valorJson;
    final semAspas =
        bruto.startsWith('"') && bruto.endsWith('"') && bruto.length >= 2
        ? bruto.substring(1, bruto.length - 1)
        : bruto;

    return switch (c.tipo) {
      'booleano' => semAspas == 'true' ? 'Sim' : 'Não',
      'lista' =>
        c.opcoes.where((o) => o.id == semAspas).map((o) => o.rotulo).firstOrNull
            // Opção que saiu do catálogo depois de preenchida: mostra o id, que
            // é o que está gravado, em vez de esconder o valor.
            ??
            semAspas,
      _ => semAspas,
    };
  }
}

/// P5 — confirma antes de apagar: anotação some para todo mundo.
Future<void> _excluirNota(
  BuildContext context,
  FichaController controller,
  int notaId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Excluir a anotação?'),
      content: const Text('Ela some para todos os atendentes.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogo).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;
  final erro = await controller.removerNota(notaId);
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro.message)));
  }
}

/// P5 — a história do atendimento, do jeito que a v1 mostrava: aberto, movido,
/// anotado, etiquetado, encerrado.
Future<void> _abrirTimeline(BuildContext context, int atendimentoId) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 560,
        height: 480,
        child: _Timeline(atendimentoId: atendimentoId),
      ),
    ),
  );
}

class _Timeline extends StatefulWidget {
  final int atendimentoId;

  const _Timeline({required this.atendimentoId});

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  late Future<ReturnSuccessOrError<List<EventoDaTimeline>, FichaError>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = inject<ListarTimelineUsecase>()(
      ListarTimelineParameters(atendimentoId: widget.atendimentoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'História do atendimento',
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
                ReturnSuccessOrError<List<EventoDaTimeline>, FichaError>
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
                        icon: Icons.history,
                        title: 'Sem história ainda',
                        subtitle: 'Movimentos e anotações aparecem aqui.',
                      ),
                    Success(:final value) => ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: value.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final e = value[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_icone(e.tipo), size: 16, color: muted),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.descricao),
                                  Text(
                                    [
                                      _quando(e.quando),
                                      if (e.autor.isNotEmpty) e.autor,
                                      if (e.automatico) 'automático',
                                    ].join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

  static IconData _icone(String tipo) => switch (tipo) {
    'aberto' => Icons.play_circle_outline,
    'movido' => Icons.swap_horiz,
    'nota' => Icons.sticky_note_2_outlined,
    'etiqueta' => Icons.label_outline,
    'avaliado' => Icons.star_outline,
    'encerrado' => Icons.flag_outlined,
    _ => Icons.circle_outlined,
  };
}
