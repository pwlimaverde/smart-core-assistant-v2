library;

// O menu é exportado porque o app do tenant o entrega ao módulo operacional:
// o quadro de atendimento é a primeira tela depois do login e precisa dele,
// mas aquele módulo não pode depender deste.
export 'src/shared/widgets/tenant_drawer.dart' show TenantDrawer;
export 'src/tenant_module.dart' show TenantModule;
// Mesmo motivo do menu: a faixa de aviso de WhatsApp fora do ar aparece no
// quadro, que é do módulo operacional, mas conexão é assunto deste módulo.
export 'src/shared/widgets/aviso_conexao.dart' show AvisoConexao;
// Composição das faixas do topo do quadro: o slot do operacional_module aceita
// um widget só, e há dois avisos possíveis (assinatura e conexão).
export 'src/shared/widgets/avisos_do_quadro.dart' show AvisosDoQuadro;
// C3: o quadro (do operacional_module) precisa procurar clientes para abrir
// uma conversa, e cadastro de cliente é assunto deste módulo. Mesmo desenho do
// menu e dos avisos — a dependência corre nesta direção.
export 'src/shared/buscar_contatos_do_tenant.dart' show buscarContatosDoTenant;
// B2: o treinamento mora noutro módulo, que não conhece a sessão; o app lhe
// entrega esta pergunta pronta.
export 'src/shared/permissoes.dart' show sessaoPodeAlterar, usuarioDaSessao;
