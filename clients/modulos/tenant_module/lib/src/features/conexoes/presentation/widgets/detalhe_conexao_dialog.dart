import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/errors/conexoes_errors.dart';
import '../../domain/model/conexao.dart';
import '../controllers/conexoes_controllers.dart';

/// P7 — o detalhe da conexão.
///
/// O cartão da lista mostra o essencial; o que ele não cabe é justamente o que
/// se procura quando algo está errado: quando o estado foi conferido pela
/// última vez, qual é o identificador da instância no provedor (o que vai para
/// o suporte) e quanto se perde ao encerrar a sessão agora.
Future<void> mostrarDetalheDaConexao(
  BuildContext context, {
  required ConexoesController controller,
  required int id,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 480,
        child: _Detalhe(controller: controller, id: id),
      ),
    ),
  );
}

class _Detalhe extends StatefulWidget {
  final ConexoesController controller;
  final int id;

  const _Detalhe({required this.controller, required this.id});

  @override
  State<_Detalhe> createState() => _DetalheState();
}

class _DetalheState extends State<_Detalhe> {
  late Future<ReturnSuccessOrError<DetalheConexao, ConexoesError>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = widget.controller.detalhe(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: FutureBuilder<ReturnSuccessOrError<DetalheConexao, ConexoesError>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return switch (snapshot.data!) {
            Failure(:final error) => SizedBox(
              height: 160,
              child: AppErrorView(message: error.message),
            ),
            Success(:final value) => _Corpo(detalhe: value),
          };
        },
      ),
    );
  }
}

class _Corpo extends StatelessWidget {
  final DetalheConexao detalhe;

  const _Corpo({required this.detalhe});

  @override
  Widget build(BuildContext context) {
    final c = detalhe.conexao;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.nome,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const Divider(height: AppSpacing.xl),
        _Campo(rotulo: 'Situação', valor: c.situacao.rotulo),
        _Campo(
          rotulo: 'Número pareado',
          valor: c.telefone.isEmpty ? 'Nenhum — falta ler o QR' : c.telefone,
        ),
        _Campo(
          rotulo: 'Roteia para',
          valor: c.departamentoId == 0
              ? 'Nenhum departamento (primeiro fluxo ativo)'
              : c.departamentoNome,
        ),
        _Campo(
          rotulo: 'Última conferência',
          // "Nunca" é informação, não ausência dela: diz que o estado mostrado
          // é o do banco e pode estar velho.
          valor: detalhe.ultimaChecagem == null
              ? 'Nunca conferida com o provedor'
              : _quando(detalhe.ultimaChecagem!),
        ),
        _Campo(
          rotulo: 'No provedor',
          valor: detalhe.instanciaNoProvedor.isEmpty
              ? 'Ainda não criada'
              : detalhe.instanciaNoProvedor,
        ),
        const Divider(height: AppSpacing.xl),
        // O que se perde ao encerrar a sessão agora. Os dois números são do
        // tenant, não desta conexão — o atendimento não guarda por onde entrou.
        Text(
          'No tenant agora',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        _Campo(
          rotulo: 'Conversas abertas',
          valor: '${detalhe.atendimentosAbertos}',
        ),
        _Campo(
          rotulo: 'Mensagens em 24h',
          valor: '${detalhe.mensagens24h}',
        ),
      ],
    );
  }

  static String _quando(DateTime d) {
    String dois(int v) => v.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)} às ${dois(d.hour)}:${dois(d.minute)}';
  }
}

class _Campo extends StatelessWidget {
  final String rotulo;
  final String valor;

  const _Campo({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              rotulo,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted),
            ),
          ),
          Expanded(child: SelectableText(valor)),
        ],
      ),
    );
  }
}
