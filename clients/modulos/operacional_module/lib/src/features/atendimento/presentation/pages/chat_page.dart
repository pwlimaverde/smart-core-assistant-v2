import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';

import '../controllers/chat_controller.dart';
import '../controllers/chat_state.dart';
import '../controllers/ficha_controller.dart';
import '../widgets/chat_connection_badge.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/painel_ficha.dart';

/// Chat lateral de um atendimento (WS-6.3): histórico + stream realtime +
/// envio outbound. Consome `AtendimentoDataSource.streamAtendimentos` (via
/// [ChatController]) com reconexão automática (backoff exponencial + jitter)
/// e exibe o estado da conexão ([ChatConnectionBadge]).
///
/// Cada abertura registra um [ChatController] de escopo próprio (rota) — o
/// controller é fechado (stream cancelado) quando a tela é descartada.
class ChatPage extends StatefulWidget {
  final int atendimentoId;

  const ChatPage({super.key, required this.atendimentoId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _controller;
  late final FichaController _ficha;
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      getThreadUsecase: inject(),
      sendUsecase: inject(),
      eventos: inject(),
    );
    // Controller próprio: a ficha pode falhar sem derrubar a conversa, e um
    // estado só levaria as mensagens junto com o painel.
    _ficha = FichaController(
      carregar: inject(),
      criarEtiqueta: inject(),
      alternar: inject(),
      criarNota: inject(),
    );
    _controller.abrir(widget.atendimentoId);
    _ficha.abrir(widget.atendimentoId);
  }

  @override
  void dispose() {
    _controller.close();
    _ficha.close();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Atendimento #${widget.atendimentoId}',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final conversa = BlocBuilder<ChatController, ViewState<ChatViewModel>>(
            bloc: _controller,
            builder: (context, state) {
              return switch (state) {
                InitialState() || LoadingState() => const Center(
                  child: CircularProgressIndicator(),
                ),
                ErrorState(:final error) => AppErrorView(
                  message: error.message,
                  onRetry: () => _controller.abrir(widget.atendimentoId),
                ),
                SuccessState(:final data) => _ChatBody(
                  viewModel: data,
                  inputController: _inputController,
                  onEnviar: _enviar,
                ),
              };
            },
          );

          // Em janela estreita a ficha some em vez de espremer a conversa: ler
          // e responder é o que não pode ficar sem espaço. As etiquetas
          // continuam visíveis no cartão do quadro.
          if (constraints.maxWidth < 900) return conversa;

          return Row(
            children: [
              Expanded(child: conversa),
              PainelFicha(controller: _ficha),
            ],
          );
        },
      ),
    );
  }

  Future<void> _enviar() async {
    final texto = _inputController.text.trim();
    if (texto.isEmpty) return;
    _inputController.clear();
    final erro = await _controller.enviar(texto);
    if (erro != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

class _ChatBody extends StatelessWidget {
  final ChatViewModel viewModel;
  final TextEditingController inputController;
  final VoidCallback onEnviar;

  const _ChatBody({
    required this.viewModel,
    required this.inputController,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ChatConnectionBadge(status: viewModel.connectionStatus),
        Expanded(
          child: viewModel.mensagens.isEmpty
              ? const AppEmptyView(
                  icon: Icons.chat_bubble_outline,
                  title: 'Nenhuma mensagem ainda',
                  subtitle:
                      'Envie a primeira mensagem para iniciar a conversa.',
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: viewModel.mensagens.length,
                  itemBuilder: (context, index) {
                    final mensagem = viewModel
                        .mensagens[viewModel.mensagens.length - 1 - index];
                    return ChatMessageBubble(mensagem: mensagem);
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Mensagem',
                  hint: 'Digite uma mensagem…',
                  controller: inputController,
                  onSubmitted: (_) => onEnviar(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: onEnviar,
                tooltip: 'Enviar mensagem',
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
