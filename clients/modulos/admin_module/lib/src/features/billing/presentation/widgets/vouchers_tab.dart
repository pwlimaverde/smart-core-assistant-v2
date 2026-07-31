// `hide`: o barrel reexporta os stubs gerados, que trazem tipos de mesmo
// nome. Aqui valem os modelos de domínio.
import 'package:dependencies_module/dependencies_module.dart'
    hide Plan, Voucher, VoucherRedemption;

import '../../domain/model/plan.dart';
import '../../domain/model/voucher.dart';
import '../controllers/billing_controller.dart';

/// Aba "Vouchers" do painel de faturamento.
///
/// Um voucher **não é cupom de desconto**: ele concede um plano por um período,
/// e é o meio de pagamento do cadastro enquanto não há gateway. Por isso mora
/// aqui, junto de planos e assinaturas, e não numa tela de marketing.
final class VouchersTab extends StatelessWidget {
  final List<Voucher> vouchers;
  final List<Plan> planos;
  final BillingController controller;

  const VouchersTab({
    super.key,
    required this.vouchers,
    required this.planos,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Códigos de ativação',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Novo voucher'),
              // Sem plano cadastrado não há o que conceder.
              onPressed: planos.isEmpty
                  ? null
                  : () => _abrirCriacao(context, planos, controller),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: vouchers.isEmpty
              ? const Center(
                  child: Text('Nenhum voucher criado até agora.'),
                )
              : ListView.separated(
                  itemCount: vouchers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _LinhaVoucher(
                    voucher: vouchers[i],
                    controller: controller,
                  ),
                ),
        ),
      ],
    );
  }
}

class _LinhaVoucher extends StatelessWidget {
  final Voucher voucher;
  final BillingController controller;

  const _LinhaVoucher({required this.voucher, required this.controller});

  @override
  Widget build(BuildContext context) {
    final situacao = voucher.situacaoEm(DateTime.now());
    final usos = voucher.maxResgates == 0
        ? '${voucher.resgatesUsados} usos (ilimitado)'
        : '${voucher.resgatesUsados}/${voucher.maxResgates} usos';

    return Card(
      child: ListTile(
        leading: _Selo(situacao: situacao),
        title: Row(
          children: [
            SelectableText(
              voucher.codigo,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '· ${voucher.planName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Text(
          [
            '${voucher.duracaoDias} dias',
            usos,
            if (voucher.revogado && voucher.motivoRevogacao.isNotEmpty)
              'revogado: ${voucher.motivoRevogacao}',
            if (voucher.descricao.isNotEmpty) voucher.descricao,
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.receipt_long),
              tooltip: 'Ver resgates',
              onPressed: () => _abrirResgates(context, voucher, controller),
            ),
            if (!voucher.revogado)
              IconButton(
                icon: const Icon(Icons.block),
                tooltip: 'Revogar',
                onPressed: () => _abrirRevogacao(context, voucher, controller),
              ),
          ],
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final SituacaoVoucher situacao;

  const _Selo({required this.situacao});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (cor, icone) = switch (situacao) {
      SituacaoVoucher.ativo => (Colors.green, Icons.check_circle_outline),
      SituacaoVoucher.agendado => (Colors.blueGrey, Icons.schedule),
      SituacaoVoucher.esgotado => (Colors.orange, Icons.hourglass_disabled),
      SituacaoVoucher.expirado => (Colors.orange, Icons.event_busy),
      SituacaoVoucher.revogado => (scheme.error, Icons.block),
    };

    return Tooltip(
      message: situacao.rotulo,
      child: Icon(icone, color: cor),
    );
  }
}

/// Diálogo de criação.
Future<void> _abrirCriacao(
  BuildContext context,
  List<Plan> planos,
  BillingController controller,
) async {
  final codigo = TextEditingController();
  final descricao = TextEditingController();
  final duracao = TextEditingController(text: '180');
  final maxResgates = TextEditingController(text: '1');
  var planoId = planos.first.id;

  final criar = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Novo voucher'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codigo,
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    helperText: 'Maiúsculas e minúsculas dão no mesmo.',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descricao,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (interna)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: planoId,
                  decoration: const InputDecoration(labelText: 'Plano'),
                  items: [
                    for (final p in planos)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => planoId = v ?? planoId),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: duracao,
                  decoration: const InputDecoration(
                    labelText: 'Duração concedida (dias)',
                    helperText: '180 ≈ 6 meses.',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxResgates,
                  decoration: const InputDecoration(
                    labelText: 'Máximo de resgates',
                    helperText: '0 = ilimitado (campanha aberta).',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Criar'),
          ),
        ],
      ),
    ),
  );

  if (criar != true || !context.mounted) return;

  final res = await controller.createVoucher(
    codigo: codigo.text.trim(),
    descricao: descricao.text.trim(),
    planId: planoId,
    duracaoDias: int.tryParse(duracao.text.trim()) ?? 0,
    maxResgates: int.tryParse(maxResgates.text.trim()) ?? 1,
  );
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          Success() => 'Voucher criado.',
          Failure(:final error) => error.message,
        },
      ),
    ),
  );
}

/// Diálogo de revogação. O texto deixa explícito o que a revogação **não** faz —
/// é a dúvida que aparece na hora de clicar.
Future<void> _abrirRevogacao(
  BuildContext context,
  Voucher voucher,
  BillingController controller,
) async {
  final motivo = TextEditingController();

  final confirmar = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Revogar ${voucher.codigo}?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O código deixa de ser aceito em novos cadastros. '
              'As contas que já o resgataram continuam ativas até o fim do '
              'período contratado.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivo,
              decoration: const InputDecoration(
                labelText: 'Motivo (fica no registro)',
              ),
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Revogar'),
        ),
      ],
    ),
  );

  if (confirmar != true || !context.mounted) return;

  final res = await controller.revokeVoucher(
    voucherId: voucher.id,
    motivo: motivo.text.trim(),
  );
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          // `false` = já estava revogado. Não é erro, mas o superusuário
          // precisa saber que o clique dele não mudou nada.
          Success(:final value) =>
            value ? 'Voucher revogado.' : 'Este voucher já estava revogado.',
          Failure(:final error) => error.message,
        },
      ),
    ),
  );
}

/// Histórico de resgates, carregado sob demanda.
Future<void> _abrirResgates(
  BuildContext context,
  Voucher voucher,
  BillingController controller,
) async {
  final res = await controller.listRedemptions(voucher.id);
  if (!context.mounted) return;

  switch (res) {
    case Failure(:final error):
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    case Success(:final value):
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Resgates de ${voucher.codigo}'),
          content: SizedBox(
            width: 520,
            child: value.isEmpty
                ? const Text('Este voucher ainda não foi usado.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: value.length,
                    itemBuilder: (context, i) {
                      final r = value[i];
                      return ListTile(
                        dense: true,
                        title: SelectableText(r.tenantId),
                        subtitle: Text(
                          'até ${_data(r.periodoFim)} · resgatado em '
                          '${_data(r.redeemedAt)}'
                          '${r.ip.isEmpty ? '' : ' · ${r.ip}'}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
  }
}

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
