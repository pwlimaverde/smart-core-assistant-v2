import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/tenant_config.dart';
import '../controllers/tenant_config_controller.dart';
import '../widgets/admin_drawer.dart';

class TenantConfigPage extends StatefulWidget {
  const TenantConfigPage({super.key});

  @override
  State<TenantConfigPage> createState() => _TenantConfigPageState();
}

class _TenantConfigPageState extends State<TenantConfigPage> with SingleTickerProviderStateMixin {
  late final TenantConfigController _controller;
  final _tenantIdController = TextEditingController();
  late TabController _tabController;

  // Controllers dos campos
  final _dadosEmpresaCtrl = TextEditingController();
  final _personaBotCtrl = TextEditingController();
  final _botAgentNameCtrl = TextEditingController();
  final _msgFallbackCtrl = TextEditingController();
  final _msgSemInfoCtrl = TextEditingController();
  final _msgTransferenciaCtrl = TextEditingController();

  final _llmClassCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _llmTempCtrl = TextEditingController();
  final _transcProviderCtrl = TextEditingController();
  final _transcModelCtrl = TextEditingController();
  final _visionProviderCtrl = TextEditingController();
  final _visionModelCtrl = TextEditingController();
  final _embedClassCtrl = TextEditingController();
  final _embedModelCtrl = TextEditingController();

  final _chunkSizeCtrl = TextEditingController();
  final _chunkOverlapCtrl = TextEditingController();
  final _similarityThreshCtrl = TextEditingController();
  final _vectorDistCtrl = TextEditingController();

  final _openaiKeyCtrl = TextEditingController();
  final _groqKeyCtrl = TextEditingController();
  final _googleKeyCtrl = TextEditingController();

  bool _hasFetched = false;

  @override
  void initState() {
    super.initState();
    _controller = inject<TenantConfigController>();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tenantIdController.dispose();
    _dadosEmpresaCtrl.dispose();
    _personaBotCtrl.dispose();
    _botAgentNameCtrl.dispose();
    _msgFallbackCtrl.dispose();
    _msgSemInfoCtrl.dispose();
    _msgTransferenciaCtrl.dispose();
    _llmClassCtrl.dispose();
    _modelCtrl.dispose();
    _llmTempCtrl.dispose();
    _transcProviderCtrl.dispose();
    _transcModelCtrl.dispose();
    _visionProviderCtrl.dispose();
    _visionModelCtrl.dispose();
    _embedClassCtrl.dispose();
    _embedModelCtrl.dispose();
    _chunkSizeCtrl.dispose();
    _chunkOverlapCtrl.dispose();
    _similarityThreshCtrl.dispose();
    _vectorDistCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _groqKeyCtrl.dispose();
    _googleKeyCtrl.dispose();
    super.dispose();
  }

  void _loadConfig(String tenantId) {
    if (tenantId.trim().isEmpty) return;
    _controller.fetchConfig(tenantId.trim());
    setState(() {
      _hasFetched = true;
    });
  }

  void _populateFields(TenantConfig config) {
    _dadosEmpresaCtrl.text = config.dadosEmpresa;
    _personaBotCtrl.text = config.personaBot;
    _botAgentNameCtrl.text = config.botAgentName;
    _msgFallbackCtrl.text = config.msgFallback;
    _msgSemInfoCtrl.text = config.msgSemInfo;
    _msgTransferenciaCtrl.text = config.msgTransferencia;

    _llmClassCtrl.text = config.llmClass;
    _modelCtrl.text = config.model;
    _llmTempCtrl.text = config.llmTemperature;
    _transcProviderCtrl.text = config.transcriptionProvider;
    _transcModelCtrl.text = config.transcriptionModel;
    _visionProviderCtrl.text = config.visionProvider;
    _visionModelCtrl.text = config.visionModel;
    _embedClassCtrl.text = config.embeddingsClass;
    _embedModelCtrl.text = config.embeddingsModel;

    _chunkSizeCtrl.text = config.chunkSize.toString();
    _chunkOverlapCtrl.text = config.chunkOverlap.toString();
    _similarityThreshCtrl.text = config.similarityThreshold;
    _vectorDistCtrl.text = config.vectorDistanceThreshold;

    _openaiKeyCtrl.text = config.apiKeys['openai_api_key'] ?? '';
    _groqKeyCtrl.text = config.apiKeys['groq_api_key'] ?? '';
    _googleKeyCtrl.text = config.apiKeys['google_api_key'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configurações por Tenant',
      drawer: const AdminDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parâmetros do Tenant',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'ID do Tenant (UUID)',
                      hint: 'Informe o ID do Tenant',
                      controller: _tenantIdController,
                      onSubmitted: _loadConfig,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () => _loadConfig(_tenantIdController.text),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: const Text('Carregar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_hasFetched)
              Expanded(
                child: ViewStateBuilder<TenantConfigController, TenantConfig>(
                  controller: _controller,
                  onSuccess: (context, config) {
                    // Preenche os campos de texto na primeira renderização bem sucedida
                    _populateFields(config);
                    
                    return Column(
                      children: [
                        TabBar(
                          controller: _tabController,
                          labelColor: Theme.of(context).colorScheme.primary,
                          unselectedLabelColor: Theme.of(context).hintColor,
                          tabs: const [
                            Tab(icon: Icon(Icons.smart_toy), text: 'Bot & Persona'),
                            Tab(icon: Icon(Icons.psychology), text: 'IA & Modelos'),
                            Tab(icon: Icon(Icons.folder_shared), text: 'RAG & Vetores'),
                            Tab(icon: Icon(Icons.vpn_key), text: 'API Keys'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildBotTab(),
                              _buildIaTab(),
                              _buildRagTab(),
                              _buildKeysTab(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          label: 'Salvar Configurações',
                          onPressed: _saveConfig,
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text('Informe o ID de um Tenant e clique em Carregar.'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          AppTextField(
            label: 'Nome do Agente (Bot Agent Name)',
            controller: _botAgentNameCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Dados da Empresa (Contexto)',
            controller: _dadosEmpresaCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Persona do Bot (System Prompt)',
            controller: _personaBotCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Mensagem de Fallback',
            controller: _msgFallbackCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Mensagem Sem Informação',
            controller: _msgSemInfoCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Mensagem de Transferência',
            controller: _msgTransferenciaCtrl,
          ),
        ],
      ),
    );
  }

  Widget _buildIaTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          AppTextField(
            label: 'Classe da LLM (ex: openai, groq)',
            controller: _llmClassCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Modelo da LLM (ex: gpt-4o)',
            controller: _modelCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Temperatura (ex: 0.7)',
            controller: _llmTempCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Provedor de Transcrição de Áudio',
            controller: _transcProviderCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Modelo de Transcrição',
            controller: _transcModelCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Provedor de Visão Computacional',
            controller: _visionProviderCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Modelo de Visão',
            controller: _visionModelCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Classe de Embeddings',
            controller: _embedClassCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Modelo de Embeddings',
            controller: _embedModelCtrl,
          ),
        ],
      ),
    );
  }

  Widget _buildRagTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          AppTextField(
            label: 'Tamanho do Chunk (Caracteres)',
            controller: _chunkSizeCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Sobreposição do Chunk (Overlap)',
            controller: _chunkOverlapCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Limiar de Similaridade (ex: 0.75)',
            controller: _similarityThreshCtrl,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Limiar de Distância Vetorial',
            controller: _vectorDistCtrl,
          ),
        ],
      ),
    );
  }

  Widget _buildKeysTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          AppTextField(
            label: 'OpenAI API Key',
            controller: _openaiKeyCtrl,
            obscureText: true,
            obscureToggle: true,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Groq API Key',
            controller: _groqKeyCtrl,
            obscureText: true,
            obscureToggle: true,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Google Gemini API Key',
            controller: _googleKeyCtrl,
            obscureText: true,
            obscureToggle: true,
          ),
        ],
      ),
    );
  }

  Future<void> _saveConfig() async {
    final tenantId = _tenantIdController.text.trim();
    if (tenantId.isEmpty) return;

    final config = TenantConfig(
      dadosEmpresa: _dadosEmpresaCtrl.text.trim(),
      personaBot: _personaBotCtrl.text.trim(),
      botAgentName: _botAgentNameCtrl.text.trim(),
      msgFallback: _msgFallbackCtrl.text.trim(),
      msgSemInfo: _msgSemInfoCtrl.text.trim(),
      msgTransferencia: _msgTransferenciaCtrl.text.trim(),
      llmClass: _llmClassCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      llmTemperature: _llmTempCtrl.text.trim(),
      transcriptionProvider: _transcProviderCtrl.text.trim(),
      transcriptionModel: _transcModelCtrl.text.trim(),
      visionProvider: _visionProviderCtrl.text.trim(),
      visionModel: _visionModelCtrl.text.trim(),
      embeddingsClass: _embedClassCtrl.text.trim(),
      embeddingsModel: _embedModelCtrl.text.trim(),
      chunkSize: int.tryParse(_chunkSizeCtrl.text.trim()) ?? 0,
      chunkOverlap: int.tryParse(_chunkOverlapCtrl.text.trim()) ?? 0,
      similarityThreshold: _similarityThreshCtrl.text.trim(),
      vectorDistanceThreshold: _vectorDistCtrl.text.trim(),
      apiKeys: {
        'openai_api_key': _openaiKeyCtrl.text.trim(),
        'groq_api_key': _groqKeyCtrl.text.trim(),
        'google_api_key': _googleKeyCtrl.text.trim(),
      },
    );

    final res = await _controller.updateConfig(
      tenantId: tenantId,
      config: config,
    );

    if (mounted) {
      if (res is ErrorReturn) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar configurações: ${(res as ErrorReturn).result.message}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas com sucesso!')),
        );
      }
    }
  }
}
