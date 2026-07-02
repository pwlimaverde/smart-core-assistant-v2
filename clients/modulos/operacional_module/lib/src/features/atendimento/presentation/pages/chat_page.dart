import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';

import '../controllers/chat_controller.dart';
import '../controllers/chat_state.dart';
import '../widgets/chat_connection_badge.dart';
import '../widgets/chat_message_bubble.dart';

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
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      getThreadUsecase: inject(),
      sendUsecase: inject(),
      service: inject(),
    );
    _controller.abrir(widget.atendimentoId);
  }

  @override
  void dispose() {
    _controller.close();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Atendimento #${widget.atendimentoId}',
      body: BlocBuilder<ChatController, ViewState<ChatViewModel>>(
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
    final colors = context.colors;

    return Column(
      children: [
        ChatConnectionBadge(status: viewModel.connectionStatus),
        Expanded(
          child: viewModel.mensagens.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma mensagem ainda.',
                    style: TextStyle(color: colors.fgMuted),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: viewModel.mensagens.length,
                  itemBuilder: (context, index) {
                    final mensagem =
                        viewModel.mensagens[viewModel.mensagens.length - 1 - index];
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
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
