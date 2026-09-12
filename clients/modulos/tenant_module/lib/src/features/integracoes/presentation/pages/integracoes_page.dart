import 'package:dependencies_module/dependencies_module.dart';
// `Clipboard` não vem pelo dependencies_module (que reexporta material, não
// services). Import direto, como fazem as outras telas que copiam texto.
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/mcp_grant.dart';
import '../controllers/integracoes_controller.dart';

/// URL do servidor MCP que o usuário cola no conector do cliente de IA.
///
/// É a única coisa que ele precisa copiar — e ela não é segredo: é um endereço
/// público. O acesso em si acontece no navegador, com login e consentimento.
/// Esta tela **não** gera token, e é de propósito: o desenho anterior, com
/// credencial copiada e colada, tinha a classe inteira de risco de "segredo
/// esquecido num arquivo de configuração".
///
/// Vem do [AppConfig], **por ambiente**. Estava fixo no domínio de produção, e
/// isso quebrava o app de dev: a descoberta OAuth de cada ambiente declara o
/// `resource` com o próprio domínio, então colar o endereço de produção num app
/// apontado para dev faz o cliente recusar por divergência. Os dois domínios
/// respondem — por isso o defeito não aparecia numa checagem superficial.
String get _urlDoServidorMcp => inject<AppConfig>().mcpEndpoint;

/// Instalação por linha de comando (Claude Code, Cursor).
///
/// É o único cliente em que "instalar direto" é literalmente um comando. No
/// Claude de janela e no ChatGPT não existe link de instalação para servidor
/// **remoto**: a documentação da Anthropic descreve apenas colar o endereço em
/// Conectores, e o instalador de um clique (`.mcpb`) vale só para servidor
/// local. Daí o endereço acima continuar sendo o caminho de lá.
///
/// Derivado do endereço, e não escrito à mão: duplicá-lo faria uma troca de
/// domínio corrigir só metade da tela.
String get _comandoClaudeCode =>
    'claude mcp add --transport http smartcore $_urlDoServidorMcp';

/// Tradução dos escopos técnicos para o que o usuário entende.
///
/// A tela nunca mostra `atendimentos:write` cru: quem lê esta lista precisa
/// decidir se aquele acesso deveria existir, e para isso o rótulo tem de estar
/// na língua do negócio dele.
const _rotulosDeEscopo = <String, String>{
  'atendimentos:read': 'Ver atendimentos e mensagens',
  'atendimentos:write': 'Enviar mensagens e mover atendimentos',
  'clientes:read': 'Ver contatos',
  'clientes:write': 'Criar e editar contatos',
  'operacional:read': 'Ver departamentos e equipe',
  'operacional:admin': 'Gerenciar departamentos, equipe e conexões',
  'kanban:admin': 'Gerenciar todos os fluxos',
  'treinamento:read': 'Ver a base de conhecimento',
  'treinamento:write': 'Editar a base de conhecimento',
  'financeiro:read': 'Ver dados financeiros',
  'financeiro:write': 'Registrar lançamentos financeiros',
  'configuracoes:read': 'Ver configurações',
  'configuracoes:write': 'Alterar configurações e integrações',
  'tenant:admin': 'Administrar tudo no negócio',
};

String _rotuloDe(String escopo) => _rotulosDeEscopo[escopo] ?? escopo;

class IntegracoesPage extends StatefulWidget {
  const IntegracoesPage({super.key});

  @override
  State<IntegracoesPage> createState() => _IntegracoesPageState();
}

class _IntegracoesPageState extends State<IntegracoesPage> {
  late final IntegracoesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<IntegracoesController>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.fetchGrants(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Aplicativos conectados',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchGrants,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aplicativos de IA conectados',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Estes aplicativos podem agir na sua conta com as permissões que '
              'você concedeu — nunca mais do que você mesmo pode fazer aqui.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _blocoComoConectar(context),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<IntegracoesController, List<McpGrant>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.fetchGrants,
                ),
                onSuccess: (context, grants) {
                  if (grants.isEmpty) {
                    return const AppEmptyView(
                      icon: Icons.smart_toy_outlined,
                      title: 'Nenhum aplicativo conectado',
                      subtitle:
                          'Siga os passos acima no Claude, no ChatGPT ou no '
                          'Cursor para conectar um assistente de IA à sua conta.',
                    );
                  }
                  return ListView.separated(
                    itemCount: grants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) =>
                        _cartaoDoApp(context, grants[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bloco "Conectar um agente": só a URL, porque não há token a copiar.
  Widget _blocoComoConectar(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Conectar um assistente de IA',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'No Claude ou no ChatGPT, abra as configurações de conectores, '
            'escolha adicionar um conector personalizado e informe o endereço '
            'abaixo. Você será levado a esta conta para entrar e escolher o que '
            'o assistente poderá fazer.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _urlDoServidorMcp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copiar endereço',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _urlDoServidorMcp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Endereço copiado.')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Não há senha nem token para copiar. Se algum aplicativo pedir uma '
            'chave de acesso para conectar aqui, desconfie.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 32),
          // Claude Code e Cursor instalam por linha de comando — é o único
          // cliente em que "instalar direto" é literalmente um comando só.
          //
          // No Claude de janela e no ChatGPT **não existe** link de instalação:
          // a documentação da Anthropic descreve apenas colar o endereço em
          // Conectores, e o instalador de um clique (`.mcpb`) vale só para
          // servidor LOCAL, não para servidor remoto com OAuth como o nosso.
          // Por isso o endereço acima continua sendo o caminho de lá.
          Text(
            'No Claude Code ou no Cursor',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cole este comando no terminal. Na primeira vez ele abre o '
            'navegador para você entrar e autorizar.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _comandoClaudeCode,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copiar comando',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _comandoClaudeCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comando copiado.')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cartaoDoApp(BuildContext context, McpGrant grant) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                color: grant.podeAlterar
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // `clientName` é texto declarado pelo próprio aplicativo.
                    // O Flutter não interpreta markup em `Text`, então não há
                    // risco de execução — mas o nome pode MENTIR, e é por isso
                    // que o endereço de retorno aparece logo abaixo, sempre.
                    Text(
                      grant.clientName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      grant.ehLocal
                          ? 'Programa instalado na sua máquina '
                                '(${grant.redirectHost})'
                          : 'Devolve o acesso para ${grant.redirectHost}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (grant.podeAlterar)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'altera dados',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Desconectar'),
                onPressed: () => _confirmarDesconexao(context, grant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: grant.scopes
                .map(
                  (escopo) => Chip(
                    label: Text(_rotuloDe(escopo)),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Text(
            grant.lastUsedAt == null
                ? 'Conectado em ${_data(grant.createdAt)} · ainda não foi usado'
                : 'Conectado em ${_data(grant.createdAt)} · '
                      'usado por último em ${_data(grant.lastUsedAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _confirmarDesconexao(
    BuildContext context,
    McpGrant grant,
  ) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar aplicativo?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${grant.clientName}" perde o acesso à sua conta e precisará ser '
              'conectado de novo, com sua aprovação, para voltar a funcionar.',
            ),
            const SizedBox(height: 12),
            // Honestidade sobre a janela real: a renovação é cortada na hora, mas
            // o acesso já em andamento só termina quando o token dele expira.
            // Prometer "corte imediato" seria mentir num ponto que importa —
            // quem desconecta por suspeita precisa saber disso.
            Text(
              'A renovação é cortada imediatamente. Um acesso que esteja em '
              'andamento neste instante pode continuar por alguns minutos até '
              'expirar.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );

    if (confirmou != true || !context.mounted) return;

    final resultado = await _controller.revokeGrant(grant.id);
    if (!mounted) return;

    switch (resultado) {
      case Success(:final value):
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text(
              'Aplicativo desconectado. Um acesso em andamento pode durar até '
              '$value minutos.',
            ),
          ),
        );
      case Failure(:final error):
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(SnackBar(content: Text(ErrorMessageMapper.map(error))));
    }
  }
}
