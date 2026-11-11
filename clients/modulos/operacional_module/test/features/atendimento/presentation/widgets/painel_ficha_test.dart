import 'dart:async';

import 'package:api_client/api_client.dart' show GrpcError;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/contato_da_conversa.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ficha.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/ficha_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/ficha_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/painel_ficha.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/fake_gateway.dart';

Etiqueta _etiqueta({
  required int id,
  required String nome,
  String cor = '#3b82f6',
  bool ativo = true,
}) => Etiqueta(id: id, nome: nome, cor: cor, descricao: '', ativo: ativo);

void main() {
  FichaController controllerSobre(FakeAtendimentoGateway gateway) =>
      FichaController(
        carregar: GetFichaUsecase(
          repository: GetFichaRepository(
            datasource: GetFichaDatasource(gateway: gateway),
          ),
        ),
        criarEtiqueta: CriarEtiquetaUsecase(
          repository: CriarEtiquetaRepository(
            datasource: CriarEtiquetaDatasource(gateway: gateway),
          ),
        ),
        alternar: AlternarEtiquetaUsecase(
          repository: AlternarEtiquetaRepository(
            datasource: AlternarEtiquetaDatasource(gateway: gateway),
          ),
        ),
        criarNota: CriarNotaUsecase(
          repository: CriarNotaRepository(
            datasource: CriarNotaDatasource(gateway: gateway),
          ),
        ),
        definirBot: DefinirBotDaConversaUsecase(
          repository: DefinirBotDaConversaRepository(
            datasource: DefinirBotDaConversaDatasource(gateway: gateway),
          ),
        ),
        definirValorCampo: DefinirValorCampoUsecase(
          repository: DefinirValorCampoRepository(
            datasource: DefinirValorCampoDatasource(gateway: gateway),
          ),
        ),
        // P5 — a ficha agora exclui nota e mantém o catálogo de etiquetas.
        removerNota: RemoverNotaUsecase(
          repository: RemoverNotaRepository(
            datasource: RemoverNotaDatasource(gateway: gateway),
          ),
        ),
        atualizarEtiqueta: AtualizarEtiquetaUsecase(
          repository: AtualizarEtiquetaRepository(
            datasource: AtualizarEtiquetaDatasource(gateway: gateway),
          ),
        ),
        desativarEtiqueta: DesativarEtiquetaUsecase(
          repository: DesativarEtiquetaRepository(
            datasource: DesativarEtiquetaDatasource(gateway: gateway),
          ),
        ),
        vincularCliente: VincularClienteUsecase(
          repository: VincularClienteRepository(
            datasource: VincularClienteDatasource(gateway: gateway),
          ),
        ),
        buscarClientes: BuscarClientesUsecase(
          repository: BuscarClientesRepository(
            datasource: BuscarClientesDatasource(gateway: gateway),
          ),
        ),
        salvarCliente: SalvarClienteUsecase(
          repository: SalvarClienteRepository(
            datasource: SalvarClienteDatasource(gateway: gateway),
          ),
        ),
      );

  Future<FichaController> montar(
    WidgetTester tester,
    FakeAtendimentoGateway gateway,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final controller = controllerSobre(gateway);
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PainelFicha(controller: controller)),
      ),
    );
    await controller.abrir(7);
    await tester.pumpAndSettle();
    return controller;
  }

  group('etiquetas disponíveis', () {
    test('não oferece o que já está colado na conversa', () {
      // Oferecer uma etiqueta já aplicada seria um clique sem efeito.
      final ficha = FichaAtendimento(
        catalogo: [
          _etiqueta(id: 1, nome: 'urgente'),
          _etiqueta(id: 2, nome: 'vip'),
        ],
        aplicadas: [_etiqueta(id: 1, nome: 'urgente')],
        notas: const [],
      );

      expect(ficha.disponiveis.map((e) => e.id), [2]);
    });

    test('não oferece etiqueta desativada do catálogo', () {
      final ficha = FichaAtendimento(
        catalogo: [_etiqueta(id: 3, nome: 'antiga', ativo: false)],
        aplicadas: const [],
        notas: const [],
      );

      expect(ficha.disponiveis, isEmpty);
    });

    test('etiqueta desativada JÁ aplicada continua na conversa', () {
      // Sumir com ela reescreveria o passado desta conversa.
      final ficha = FichaAtendimento(
        catalogo: [_etiqueta(id: 3, nome: 'antiga', ativo: false)],
        aplicadas: [_etiqueta(id: 3, nome: 'antiga', ativo: false)],
        notas: const [],
      );

      expect(ficha.aplicadas.single.nome, 'antiga');
      expect(ficha.disponiveis, isEmpty);
    });
  });

  group('corDaEtiqueta', () {
    test('converte o hex do catálogo', () {
      expect(corDaEtiqueta('#3b82f6'), const Color(0xFF3B82F6));
      expect(corDaEtiqueta('3b82f6'), const Color(0xFF3B82F6));
    });

    test('hex inválido não derruba o painel', () {
      expect(corDaEtiqueta(''), const Color(0xFFA98F71));
      expect(corDaEtiqueta('#zzz'), const Color(0xFFA98F71));
    });
  });

  group('PainelFicha', () {
    testWidgets('sugere o cliente cujo CPF a conversa trouxe e vincula', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: const [],
          aplicadas: const [],
          notas: const [],
        )
        ..clientesDaBusca = const [
          ClienteDaConversa(
            id: 9,
            nomeFantasia: 'Padaria Sol',
            cpf: '52998224725',
          ),
        ];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerSobre(gateway);
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PainelFicha(
              controller: controller,
              contato: const ContatoDaConversa(
                contatoId: 4,
                nome: 'Ana',
                telefone: '5588999912191',
                fotoUrl: '',
              ),
              documentos: const ['52998224725'],
            ),
          ),
        ),
      );
      await controller.abrir(7);
      await tester.pumpAndSettle();

      expect(find.textContaining('Padaria Sol'), findsOneWidget);
      await tester.tap(find.text('Vincular'));
      await tester.pumpAndSettle();
      expect(gateway.acoesDoCadastro, contains('vincular:9:4:true'));
    });

    testWidgets('mostra o nome do perfil do WhatsApp quando difere do '
        'cadastro', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: const [],
          aplicadas: const [],
          notas: const [],
        );
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerSobre(gateway);
      addTearDown(controller.close);

      // Sem `pumpAndSettle` aqui: antes de `abrir` a ficha ainda carrega.
      Future<void> mostrar(ContatoDaConversa contato) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PainelFicha(controller: controller, contato: contato),
          ),
        ),
      );

      await mostrar(
        const ContatoDaConversa(
          contatoId: 4,
          nome: 'Ana Souza',
          telefone: '5588999912191',
          fotoUrl: '',
          nomePerfilWhatsapp: 'Aninha',
        ),
      );
      await controller.abrir(7);
      await tester.pumpAndSettle();
      expect(find.text('No WhatsApp: Aninha'), findsOneWidget);

      // Igual ao nome do cadastro: a linha não se repete.
      await mostrar(
        const ContatoDaConversa(
          contatoId: 4,
          nome: 'Ana Souza',
          telefone: '5588999912191',
          fotoUrl: '',
          nomePerfilWhatsapp: 'Ana Souza',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No WhatsApp:'), findsNothing);
    });

    testWidgets('"Criar" usa o nome do perfil do WhatsApp quando o contato '
        'não tem nome', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: const [],
          aplicadas: const [],
          notas: const [],
        )
        ..clientesDaBusca = const [];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerSobre(gateway);
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PainelFicha(
              controller: controller,
              contato: const ContatoDaConversa(
                contatoId: 4,
                nome: '',
                telefone: '5588999912191',
                fotoUrl: '',
                nomePerfilWhatsapp: 'Aninha',
              ),
              documentos: const ['52998224725'],
            ),
          ),
        ),
      );
      await controller.abrir(7);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();
      // O cliente não nasce com o telefone no lugar do nome.
      expect(gateway.acoesDoCadastro, contains('salvarCliente:0:Aninha'));
    });

    testWidgets('busca antiga que responde depois não troca a lista de '
        '"Vincular a cliente"', (tester) async {
      final lenta = Completer<List<ClienteDaConversa>>();
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: const [],
          aplicadas: const [],
          notas: const [],
        )
        ..clientesDaBusca = const [
          ClienteDaConversa(id: 9, nomeFantasia: 'Padaria Sol'),
        ]
        ..buscasSeguradas['pa'] = lenta;
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerSobre(gateway);
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PainelFicha(
              controller: controller,
              contato: const ContatoDaConversa(
                contatoId: 4,
                nome: 'Ana',
                telefone: '5588999912191',
                fotoUrl: '',
              ),
            ),
          ),
        ),
      );
      await controller.abrir(7);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vincular a cliente'));
      await tester.pumpAndSettle();
      final campoDeBusca = find.widgetWithText(
        TextField,
        'Nome, CPF/CNPJ ou telefone',
      );
      expect(campoDeBusca, findsOneWidget);

      // "pa" fica presa; "pad" responde na hora.
      await tester.enterText(campoDeBusca, 'pa');
      await tester.pump();
      await tester.enterText(campoDeBusca, 'pad');
      await tester.pumpAndSettle();
      expect(find.text('Padaria Sol'), findsOneWidget);

      // A resposta de "pa" chega atrasada, com outro cliente: é descartada.
      lenta.complete(const [
        ClienteDaConversa(id: 3, nomeFantasia: 'Papelaria Lua'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Padaria Sol'), findsOneWidget);
      expect(find.text('Papelaria Lua'), findsNothing);
    });

    // Documento válido sem cliente cadastrado: a sugestão oferece "Criar".
    Future<void> montarComDocumentoNovo(
      WidgetTester tester,
      FakeAtendimentoGateway gateway,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerSobre(gateway);
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PainelFicha(
              controller: controller,
              contato: const ContatoDaConversa(
                contatoId: 4,
                nome: 'Ana',
                telefone: '5588999912191',
                fotoUrl: '',
              ),
              documentos: const ['52998224725'],
            ),
          ),
        ),
      );
      await controller.abrir(7);
      await tester.pumpAndSettle();
    }

    int contar(FakeAtendimentoGateway gateway, String prefixo) =>
        gateway.acoesDoCadastro.where((a) => a.startsWith(prefixo)).length;

    testWidgets('vínculo que falhou depois de criar não cria o cliente de '
        'novo no próximo clique', (tester) async {
      // Criar de novo duplicaria o cliente com o mesmo documento.
      final gateway = FakeAtendimentoGateway()
        ..erroVincular = GrpcError.unavailable('fora do ar');
      await montarComDocumentoNovo(tester, gateway);

      expect(find.text('Criar cliente com estes dados?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Criar'));
      await tester.pumpAndSettle();

      expect(contar(gateway, 'salvarCliente:'), 1);
      expect(contar(gateway, 'vincular:1:4:true'), 1);
      expect(find.byType(SnackBar), findsOneWidget);

      gateway.erroVincular = null;
      await tester.tap(find.widgetWithText(TextButton, 'Criar'));
      await tester.pumpAndSettle();

      expect(contar(gateway, 'salvarCliente:'), 1);
      expect(contar(gateway, 'vincular:1:4:true'), 2);
    });

    testWidgets('duplo clique em "Criar" enquanto a chamada roda cria uma '
        'vez só', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..travaSalvarCliente = Completer<void>();
      await montarComDocumentoNovo(tester, gateway);

      final botao = find.widgetWithText(TextButton, 'Criar');
      await tester.tap(botao);
      await tester.pump();

      // Ocupado: o botão fica desabilitado e o segundo toque não dispara nada.
      expect(tester.widget<TextButton>(botao).onPressed, isNull);
      await tester.tap(botao, warnIfMissed: false);
      await tester.pump();

      gateway.travaSalvarCliente!.complete();
      await tester.pumpAndSettle();

      expect(contar(gateway, 'salvarCliente:'), 1);
      expect(contar(gateway, 'vincular:1:4:true'), 1);
    });

    testWidgets('documento que muda durante "Criar" não vincula o contato ao '
        'cliente do documento anterior', (tester) async {
      // A conversa trazia o documento A; durante a criação chega mensagem e o
      // documento vira B. O cliente de A não pode ser ligado ao contato, nem
      // reaproveitado quando o atendente clicar "Criar" para B.
      final gateway = FakeAtendimentoGateway()
        ..travaSalvarCliente = Completer<void>();
      await montarComDocumentoNovo(tester, gateway);
      final controller = tester
          .widget<PainelFicha>(find.byType(PainelFicha))
          .controller;

      await tester.tap(find.widgetWithText(TextButton, 'Criar'));
      await tester.pump();

      // Mesmo painel, outro documento: dispara o didUpdateWidget da sugestão.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PainelFicha(
              controller: controller,
              contato: const ContatoDaConversa(
                contatoId: 4,
                nome: 'Ana',
                telefone: '5588999912191',
                fotoUrl: '',
              ),
              documentos: const ['11144477735'],
            ),
          ),
        ),
      );
      await tester.pump();

      gateway.travaSalvarCliente!.complete();
      await tester.pumpAndSettle();

      // A criação de A voltou com o documento já trocado: nada de vínculo,
      // só o aviso para o atendente conferir.
      expect(contar(gateway, 'salvarCliente:'), 1);
      expect(contar(gateway, 'vincular:'), 0);
      expect(find.byType(SnackBar), findsOneWidget);

      // "Criar" para B cria o cliente de B, não reusa o id de A.
      await tester.tap(find.widgetWithText(TextButton, 'Criar'));
      await tester.pumpAndSettle();

      expect(contar(gateway, 'salvarCliente:'), 2);
      // A segunda criação levou o documento B, e o vínculo usou o id dela (2),
      // não o da criação de A (1).
      expect(gateway.documentosCriados, ['52998224725', '11144477735']);
      expect(contar(gateway, 'vincular:'), 1);
      expect(gateway.acoesDoCadastro, contains('vincular:2:4:true'));
      expect(
        gateway.acoesDoCadastro.indexWhere((a) => a.startsWith('vincular:')),
        greaterThan(
          gateway.acoesDoCadastro.lastIndexWhere(
            (a) => a.startsWith('salvarCliente:'),
          ),
        ),
      );
    });

    testWidgets('mostra as etiquetas da conversa e as disponíveis', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: [
            _etiqueta(id: 1, nome: 'urgente'),
            _etiqueta(id: 2, nome: 'vip'),
          ],
          aplicadas: [_etiqueta(id: 1, nome: 'urgente')],
          notas: const [],
        );

      await montar(tester, gateway);

      expect(find.text('urgente'), findsOneWidget);
      expect(find.text('vip'), findsOneWidget);
      expect(find.text('Colar nesta conversa'), findsOneWidget);
    });

    testWidgets('a etiqueta posta pela IA tem o ✨ (P14)', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = const FichaAtendimento(
          catalogo: [],
          aplicadas: [
            Etiqueta(
              id: 7,
              nome: 'orcamento',
              cor: '#3b82f6',
              descricao: '',
              ativo: true,
              aplicadaPelaIa: true,
            ),
          ],
          notas: [],
        );

      await montar(tester, gateway);

      expect(find.text('orcamento'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('mostra o que a IA encontrou do contato (P15)', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = const FichaAtendimento(
          catalogo: [],
          aplicadas: [],
          notas: [],
          dadosDoContato: {'cidade': 'Recife'},
        );

      await montar(tester, gateway);

      // À vista, sem precisar expandir: é o que se procura aqui.
      expect(find.text('DADOS DO CONTATO'), findsOneWidget);
      expect(find.text('Recife'), findsOneWidget);
      expect(find.text('cidade'), findsOneWidget);
    });

    testWidgets('mostra a análise da IA, como o cartão do Trello', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = const FichaAtendimento(
          catalogo: [],
          aplicadas: [],
          notas: [],
          analise: AnaliseDaIa(
            intencoes: [
              (tipo: 'coleta_dados_panfleto', confianca: 0.83, vezes: 2),
              (tipo: 'saudacao', confianca: 1.0, vezes: 1),
            ],
            entidades: [(tipo: 'quantidade', valor: '2000', confianca: 0.9)],
            sentimentoLabel: 'neutro',
            sentimentoNota: 3,
            ultimaDecisao: (
              motor: 'jev',
              ato: 'coletar',
              motivo: 'coleta',
              transferiu: false,
            ),
          ),
        );

      await montar(tester, gateway);

      expect(find.text('ANÁLISE DA IA'), findsOneWidget);
      expect(find.text('coleta_dados_panfleto · 83% · 2×'), findsOneWidget);
      expect(find.text('saudacao · 100%'), findsOneWidget);
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('neutro (3)'), findsOneWidget);
      expect(find.text('Pediu dados · coleta · motor jev'), findsOneWidget);
    });

    testWidgets('decisão de ato desconhecido que transferiu diz isso', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = const FichaAtendimento(
          catalogo: [],
          aplicadas: [],
          notas: [],
          analise: AnaliseDaIa(
            sentimentoLabel: 'negativo',
            ultimaDecisao: (
              motor: '',
              ato: 'outro',
              motivo: '',
              transferiu: true,
            ),
          ),
        );

      await montar(tester, gateway);

      expect(find.text('negativo'), findsOneWidget);
      expect(find.text('Transferiu'), findsOneWidget);
    });

    testWidgets('decisão só de análise aparece traduzida', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = const FichaAtendimento(
          catalogo: [],
          aplicadas: [],
          notas: [],
          analise: AnaliseDaIa(
            ultimaDecisao: (
              motor: 'jev',
              ato: 'a_revisar',
              motivo: '',
              transferiu: false,
            ),
          ),
        );

      await montar(tester, gateway);

      expect(find.text('Resposta a revisar · motor jev'), findsOneWidget);
    });

    testWidgets('sem análise a seção não aparece', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);

      expect(find.text('ANÁLISE DA IA'), findsNothing);
    });

    testWidgets('conversa sem etiqueta diz isso, sem parecer erro', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);

      expect(find.text('Nenhuma etiqueta nesta conversa.'), findsOneWidget);
      expect(find.text('Nada anotado ainda.'), findsOneWidget);
    });

    testWidgets('colar uma etiqueta manda aplicar', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: [_etiqueta(id: 2, nome: 'vip')],
          aplicadas: const [],
          notas: const [],
        );

      await montar(tester, gateway);
      await tester.tap(find.text('vip'));
      await tester.pumpAndSettle();

      expect(gateway.etiquetaAlternada, (2, true));
    });

    testWidgets('tirar a etiqueta manda o oposto', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: [_etiqueta(id: 1, nome: 'urgente')],
          aplicadas: [_etiqueta(id: 1, nome: 'urgente')],
          notas: const [],
        );

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Tirar desta conversa'));
      await tester.pumpAndSettle();

      expect(gateway.etiquetaAlternada, (1, false));
    });

    testWidgets('as notas aparecem da mais recente para a mais antiga', (
      tester,
    ) async {
      // Quem abre a ficha quer o que aconteceu por último, não o começo.
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: const [],
          aplicadas: const [],
          notas: [
            Nota(
              id: 1,
              texto: 'primeira',
              criadoEm: DateTime.now().subtract(const Duration(days: 2)),
            ),
            Nota(id: 2, texto: 'ultima', criadoEm: DateTime.now()),
          ],
        );

      final controller = await montar(tester, gateway);

      final ficha = (controller.state as SuccessState<FichaAtendimento>).data;
      expect(ficha.notas.first.texto, 'ultima');
      expect(find.text('agora'), findsOneWidget);
    });

    testWidgets('a nota avisa que é interna, dentro da janela', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Anotar'));
      await tester.pumpAndSettle();

      expect(find.text('Só a equipe vê. O contato, nunca.'), findsOneWidget);
    });

    testWidgets('nota vazia é barrada sem chamar o servidor', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Anotar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Escreva a anotação.'), findsOneWidget);
      expect(gateway.notaRecebida, isNull);
    });

    testWidgets('anotar manda o texto e recarrega a ficha', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      final antes = gateway.chamadasFicha;

      await tester.tap(find.byTooltip('Anotar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'O que registrar'),
        'cliente pediu para ligar depois das 18h',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(gateway.notaRecebida, 'cliente pediu para ligar depois das 18h');
      expect(gateway.chamadasFicha, greaterThan(antes));
    });

    testWidgets('etiqueta sem nome é barrada', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Nova etiqueta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome da etiqueta.'), findsOneWidget);
      expect(gateway.etiquetaCriada, isNull);
    });

    testWidgets('falha da ficha não derruba nada além dela', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..erroFicha = GrpcError.unavailable('fora do ar');

      await montar(tester, gateway);

      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });
  });

  test('nome de etiqueta repetido volta com a mensagem do servidor', () async {
    // A UNIQUE (tenant, nome) diz qual nome colidiu.
    final gateway = FakeAtendimentoGateway()
      ..erroFicha = GrpcError.alreadyExists('já existe a etiqueta "urgente"');

    final res = await CriarEtiquetaUsecase(
      repository: CriarEtiquetaRepository(
        datasource: CriarEtiquetaDatasource(gateway: gateway),
      ),
    )(const CriarEtiquetaParameters(nome: 'urgente', cor: '#fff'));

    final erro = (res as Failure).error;
    expect(erro, isA<FichaRecusado>());
    expect(erro.message, contains('urgente'));
  });

  group('interruptor da IA na conversa (D3)', () {
    testWidgets('mostra que a IA está calada quando o bot está desligado', (
      tester,
    ) async {
      // É o que alguém vem procurar aqui: por que o bot parou só nesta thread.
      final gateway = FakeAtendimentoGateway()
        ..ficha = const FichaAtendimento(
          catalogo: [],
          aplicadas: [],
          notas: [],
          botPodeAtender: false,
        );

      await montar(tester, gateway);

      expect(find.text('A IA está calada nesta conversa.'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets(
      'religar a IA chega ao servidor e a ficha reflete o novo estado',
      (tester) async {
        // O caminho de volta que faltava: assumir o atendimento desliga o bot, e
        // nada devolvia o valor.
        final gateway = FakeAtendimentoGateway()
          ..ficha = const FichaAtendimento(
            catalogo: [],
            aplicadas: [],
            notas: [],
            botPodeAtender: false,
          );

        await montar(tester, gateway);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(gateway.botDefinido, isTrue);
        expect(find.text('A IA responde nesta conversa.'), findsOneWidget);
      },
    );

    testWidgets(
      'desligar não pede confirmação — é reversível no mesmo clique',
      (tester) async {
        // Ao contrário do interruptor da conexão, que cala um número inteiro.
        final gateway = FakeAtendimentoGateway();

        await montar(tester, gateway);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(gateway.botDefinido, isFalse);
      },
    );

    testWidgets('recusa do servidor não deixa o interruptor mentir', (
      tester,
    ) async {
      // A ficha recarrega ao final; se a escrita foi negada, o estado exibido
      // continua sendo o do servidor, não o do clique.
      final gateway = FakeAtendimentoGateway();
      await montar(tester, gateway);

      gateway.erroFicha = GrpcError.permissionDenied('sem escopo');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(gateway.botDefinido, isFalse);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  test('sessão expirada é distinguida de servidor fora do ar', () async {
    final gateway = FakeAtendimentoGateway()
      ..erroFicha = GrpcError.unauthenticated('expirou');

    final res = await GetFichaUsecase(
      repository: GetFichaRepository(
        datasource: GetFichaDatasource(gateway: gateway),
      ),
    )(const AtendimentoIdParameters(atendimentoId: 1));

    expect((res as Failure).error, isA<FichaSessaoExpirada>());
  });

  // ─── P5: excluir anotação ────────────────────────────────────────────────
  testWidgets('excluir anotação pede confirmação e vai ao servidor', (
    tester,
  ) async {
    final gateway = FakeAtendimentoGateway()
      ..ficha = FichaAtendimento(
        catalogo: const [],
        aplicadas: const [],
        notas: [
          Nota(
            id: 3,
            texto: 'cliente pediu retorno',
            criadoEm: DateTime(2026, 1, 1),
          ),
        ],
      );
    final controller = await montar(tester, gateway);
    await controller.abrir(1);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Excluir anotação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    expect(gateway.acoesDaFicha, contains('removerNota:3:1'));
  });
}
