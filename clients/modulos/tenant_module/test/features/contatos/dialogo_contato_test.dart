import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/features/contatos/data/datasources/contatos_datasources.dart';
import 'package:tenant_module/src/features/contatos/data/repositories/contatos_repositories.dart';
import 'package:tenant_module/src/features/contatos/domain/model/contato.dart';
import 'package:tenant_module/src/features/contatos/domain/usecases/contatos_usecases.dart';
import 'package:tenant_module/src/features/contatos/presentation/controllers/contatos_controllers.dart';
import 'package:tenant_module/src/features/contatos/presentation/widgets/dialogo_contato.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// C4 — cadastrar e corrigir cliente pela tela.
void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.CreateMyContatoRequest());
    registerFallbackValue(proto.UpdateMyContatoRequest());
    registerFallbackValue(proto.DefinirMyContatoAtivoRequest());
    registerFallbackValue(proto.ListMyContatosRequest());
  });

  setUp(() {
    client = _MockAdminClient();
    when(() => client.listMyContatos(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyContatosResponse(contatos: [])),
    );
  });

  Contato contato({
    int id = 1,
    String nome = 'Maria',
    String telefone = '5511999998888',
    String email = '',
    String perfil = '',
  }) => Contato(
    id: id,
    telefone: telefone,
    nomeContato: nome,
    nomePerfilWhatsapp: perfil,
    email: email,
    ativo: true,
    ultimaInteracao: DateTime.now(),
    cadastradoEm: DateTime.now(),
  );

  ContatosController controlador() => ContatosController(
    listar: ListarContatosUsecase(
      repository: ListarContatosRepository(
        datasource: ListarContatosDatasource(client: client),
      ),
    ),
    criar: CriarContatoUsecase(
      repository: CriarContatoRepository(
        datasource: CriarContatoDatasource(client: client),
      ),
    ),
    atualizar: AtualizarContatoUsecase(
      repository: AtualizarContatoRepository(
        datasource: AtualizarContatoDatasource(client: client),
      ),
    ),
    definirAtivo: DefinirContatoAtivoUsecase(
      repository: DefinirContatoAtivoRepository(
        datasource: DefinirContatoAtivoDatasource(client: client),
      ),
    ),
  );

  Future<ContatosController> montar(
    WidgetTester tester, {
    Contato? editando,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = controlador();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => editando == null
                  ? abrirCadastroDeContato(context, controller)
                  : abrirEdicaoDeContato(context, editando, controller),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return controller;
  }

  void respondeCriacao({String telefone = '5511999998888'}) {
    when(() => client.createMyContato(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.MyContatoResponse(
          contato: proto.MyContato(id: 9, telefone: telefone),
        ),
      ),
    );
  }

  testWidgets('cadastra mandando o telefone como foi digitado', (tester) async {
    // O cliente não normaliza: dois lugares decidindo o formato acabariam
    // discordando, e o servidor é quem grava.
    respondeCriacao();
    await montar(tester);

    await tester.enterText(find.byType(TextField).at(0), '(11) 99999-8888');
    await tester.enterText(find.byType(TextField).at(1), 'Maria Silva');
    await tester.enterText(find.byType(TextField).at(2), 'maria@exemplo.com');
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();

    final enviado =
        verify(() => client.createMyContato(captureAny())).captured.single
            as proto.CreateMyContatoRequest;
    expect(enviado.telefone, '(11) 99999-8888');
    expect(enviado.nomeContato, 'Maria Silva');
    expect(enviado.email, 'maria@exemplo.com');
  });

  testWidgets('telefone em branco nem chega ao servidor', (tester) async {
    await montar(tester);

    await tester.enterText(find.byType(TextField).at(1), 'Maria');
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Informe o telefone'), findsOneWidget);
    verifyNever(() => client.createMyContato(any()));
  });

  testWidgets('telefone repetido: a recusa fica dentro da janela', (
    tester,
  ) async {
    // Fechar e piscar um aviso atrás faria a pessoa perder o que digitou.
    when(() => client.createMyContato(any())).thenAnswer(
      (_) => falhaGrpc(
        proto.GrpcError.alreadyExists('já existe um contato com este telefone'),
      ),
    );
    await montar(tester);

    await tester.enterText(find.byType(TextField).at(0), '11999998888');
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('já existe'), findsOneWidget);
  });

  testWidgets('editar só o nome não manda telefone nenhum', (tester) async {
    // Reenviar o número atual faria a recusa por histórico aparecer em toda
    // edição de nome.
    when(
      () => client.updateMyContato(any()),
    ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
    await montar(tester, editando: contato());

    await tester.enterText(find.byType(TextField).at(1), 'Maria Souza');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final enviado =
        verify(() => client.updateMyContato(captureAny())).captured.single
            as proto.UpdateMyContatoRequest;
    expect(enviado.telefone, isEmpty);
    expect(enviado.nomeContato, 'Maria Souza');
  });

  testWidgets('mudar o número manda o número novo', (tester) async {
    when(
      () => client.updateMyContato(any()),
    ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
    await montar(tester, editando: contato());

    await tester.enterText(find.byType(TextField).at(0), '11888887777');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final enviado =
        verify(() => client.updateMyContato(captureAny())).captured.single
            as proto.UpdateMyContatoRequest;
    expect(enviado.telefone, '11888887777');
  });

  testWidgets('a edição avisa que o número trava depois da primeira conversa', (
    tester,
  ) async {
    await montar(tester, editando: contato());

    expect(find.textContaining('não tiver conversa'), findsOneWidget);
  });

  testWidgets('o cadastro explica o DDI que se assume', (tester) async {
    await montar(tester);

    expect(find.textContaining('Brasil (55)'), findsOneWidget);
  });

  testWidgets('o nome do perfil do WhatsApp aparece na edição', (tester) async {
    // É muitas vezes o único nome que se tem da pessoa, e ajuda a confirmar
    // que se está editando quem se pensa.
    await montar(
      tester,
      editando: contato(nome: '', perfil: 'Mari 💜'),
    );

    expect(find.textContaining('Mari 💜'), findsOneWidget);
  });

  testWidgets('cancelar não escreve nada', (tester) async {
    await montar(tester);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => client.createMyContato(any()));
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('tirar da lista', () {
    Future<ContatosController> montarLinha(WidgetTester tester) async {
      final controller = controlador();
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    abrirDesativacaoDeContato(context, contato(), controller),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('pede confirmação e diz o que acontece com o histórico', (
      tester,
    ) async {
      await montarLinha(tester);

      expect(find.textContaining('continuam guardadas'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => client.definirMyContatoAtivo(any()));
    });

    testWidgets('confirmando, desativa', (tester) async {
      when(
        () => client.definirMyContatoAtivo(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
      await montarLinha(tester);

      await tester.tap(find.text('Tirar da lista'));
      await tester.pumpAndSettle();

      final enviado =
          verify(
                () => client.definirMyContatoAtivo(captureAny()),
              ).captured.single
              as proto.DefinirMyContatoAtivoRequest;
      expect(enviado.id, 1);
      expect(enviado.ativo, isFalse);
    });
  });
}
