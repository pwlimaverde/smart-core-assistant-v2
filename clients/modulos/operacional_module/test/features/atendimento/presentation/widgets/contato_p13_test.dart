import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/contato_da_conversa.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/ficha_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/atendimento_card_content.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/avatar_do_contato.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/fake_gateway.dart';

/// P13 — o cartão diz quem é o contato; a foto quebrada vira iniciais.
void main() {
  AtendimentoResumo resumo({
    String nome = '',
    String telefone = '',
    String foto = '',
  }) => AtendimentoResumo(
    id: 9,
    contatoId: 4,
    status: 'fila',
    assunto: 'Orçamento',
    prioridade: 'normal',
    dataInicio: DateTime(2026, 9, 22),
    contatoNome: nome,
    contatoTelefone: telefone,
    contatoFotoUrl: foto,
  );

  Future<void> montar(WidgetTester tester, AtendimentoResumo a) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AtendimentoCardContent(atendimento: a)),
        ),
      );

  testWidgets('o cartão mostra o nome, e não "Contato #id"', (tester) async {
    await montar(tester, resumo(nome: 'Maria Souza', telefone: '5511999'));

    expect(find.text('Maria Souza'), findsOneWidget);
    expect(find.text('Contato #4'), findsNothing);
    expect(find.text('MS'), findsOneWidget);
  });

  testWidgets('sem nome, o cartão mostra o telefone', (tester) async {
    await montar(tester, resumo(telefone: '5511999998888'));

    expect(find.text('5511999998888'), findsOneWidget);
  });

  testWidgets('sem nada, cai para o id — o índice local sem rede', (
    tester,
  ) async {
    await montar(tester, resumo());

    expect(find.text('Contato #4'), findsOneWidget);
  });

  testWidgets('foto que não abre vira iniciais e avisa', (tester) async {
    var avisos = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvatarDoContato(
            nome: 'Ana Lima',
            fotoUrl: 'https://invalido.local/foto.jpg',
            aoFalharFoto: () => avisos++,
          ),
        ),
      ),
    );
    // Em teste o `Image.network` sempre falha (HttpClient devolve 400).
    await tester.pumpAndSettle();

    expect(find.text('AL'), findsOneWidget);
    expect(avisos, greaterThan(0));
  });

  test('iniciais de nome, telefone e vazio', () {
    expect(AvatarDoContato.iniciais('maria da silva'), 'MS');
    expect(AvatarDoContato.iniciais('5511999'), '5');
    expect(AvatarDoContato.iniciais('   '), '?');
  });

  test('o contato da conversa passa o forcar ao gateway', () async {
    final gateway = FakeAtendimentoGateway();
    final usecase = ObterContatoUsecase(
      repository: ObterContatoRepository(
        datasource: ObterContatoDatasource(gateway: gateway),
      ),
    );

    final r = await usecase(
      const ObterContatoParameters(atendimentoId: 9, forcar: true),
    );

    final c = (r as Success<ContatoDaConversa, dynamic>).value;
    expect(c.nomeParaExibir, 'Maria');
    expect(gateway.pedidosDeContato, [true]);
  });

  test('nomeParaExibir cai do nome ao telefone e ao id', () {
    const semNome = ContatoDaConversa(
      contatoId: 3,
      nome: '',
      telefone: '5511',
      fotoUrl: '',
    );
    const semNada = ContatoDaConversa(
      contatoId: 3,
      nome: '',
      telefone: '',
      fotoUrl: '',
    );
    expect(semNome.nomeParaExibir, '5511');
    expect(semNada.nomeParaExibir, 'Contato #3');
  });
}
