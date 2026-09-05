library;

// O menu é exportado porque o app do tenant o entrega ao módulo operacional:
// o quadro de atendimento é a primeira tela depois do login e precisa dele,
// mas aquele módulo não pode depender deste.
export 'src/shared/widgets/tenant_drawer.dart' show TenantDrawer;
export 'src/tenant_module.dart' show TenantModule;
// Mesmo motivo do menu: a faixa de aviso de WhatsApp fora do ar aparece no
// quadro, que é do módulo operacional, mas conexão é assunto deste módulo.
export 'src/shared/widgets/aviso_conexao.dart' show AvisoConexao;
