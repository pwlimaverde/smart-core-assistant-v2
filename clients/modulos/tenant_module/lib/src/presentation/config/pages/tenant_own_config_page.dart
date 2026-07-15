import 'package:dependencies_module/dependencies_module.dart';

import '../../../domain/model/tenant_config.dart';
import '../../widgets/tenant_drawer.dart';
import '../controllers/tenant_own_config_controller.dart';

class TenantOwnConfigPage extends StatefulWidget {
  const TenantOwnConfigPage({super.key});

  @override
  State<TenantOwnConfigPage> createState() => _TenantOwnConfigPageState();
}

class _TenantOwnConfigPageState extends State<TenantOwnConfigPage> {
  late final TenantOwnConfigController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<TenantOwnConfigController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.fetchConfig());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configuração do Tenant',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchConfig,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ViewStateBuilder<TenantOwnConfigController, TenantConfig>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.fetchConfig,
          ),
          onSuccess: (context, config) => _ConfigForm(
            config: config,
            onSave: (updated) async {
              final res = await _controller.updateConfig(updated);
              if (context.mounted && res is ErrorReturn<Unit>) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao salvar: ${res.result.message}')),
                );
              } else if (context.mounted && res is SuccessReturn<Unit>) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Configuração salva.')),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _ConfigForm extends StatefulWidget {
  final TenantConfig config;
  final Future<void> Function(TenantConfig updated) onSave;

  const _ConfigForm({required this.config, required this.onSave});

  @override
  State<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends State<_ConfigForm> {
  late final TextEditingController _dadosEmpresa;
  late final TextEditingController _personaBot;
  late final TextEditingController _botAgentName;
  late final TextEditingController _msgFallback;
  late final TextEditingController _msgSemInfo;
  late final TextEditingController _msgTransferencia;

  @override
  void initState() {
    super.initState();
    _dadosEmpresa = TextEditingController(text: widget.config.dadosEmpresa);
    _personaBot = TextEditingController(text: widget.config.personaBot);
    _botAgentName = TextEditingController(text: widget.config.botAgentName);
    _msgFallback = TextEditingController(text: widget.config.msgFallback);
    _msgSemInfo = TextEditingController(text: widget.config.msgSemInfo);
    _msgTransferencia = TextEditingController(text: widget.config.msgTransferencia);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AppCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Persona e Mensagens do Bot',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            AppTextField(label: 'Dados da Empresa', controller: _dadosEmpresa),
            const SizedBox(height: 16),
            AppTextField(label: 'Persona do Bot', controller: _personaBot),
            const SizedBox(height: 16),
            AppTextField(label: 'Nome do Agente', controller: _botAgentName),
            const SizedBox(height: 16),
            AppTextField(label: 'Mensagem de Fallback', controller: _msgFallback),
            const SizedBox(height: 16),
            AppTextField(label: 'Mensagem "Sem Informação"', controller: _msgSemInfo),
            const SizedBox(height: 16),
            AppTextField(label: 'Mensagem de Transferência', controller: _msgTransferencia),
            const SizedBox(height: 24),
            Text(
              'Providers (somente leitura nesta versão)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('LLM: ${widget.config.llmClass} / ${widget.config.model}'),
            Text('Transcrição: ${widget.config.transcriptionProvider} / ${widget.config.transcriptionModel}'),
            Text('Visão: ${widget.config.visionProvider} / ${widget.config.visionModel}'),
            const SizedBox(height: 24),
            Text(
              'Chaves de API (mascaradas)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...widget.config.apiKeys.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${e.key}: ${e.value}'),
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Salvar',
              onPressed: () => widget.onSave(TenantConfig(
                dadosEmpresa: _dadosEmpresa.text,
                personaBot: _personaBot.text,
                botAgentName: _botAgentName.text,
                msgFallback: _msgFallback.text,
                msgSemInfo: _msgSemInfo.text,
                msgTransferencia: _msgTransferencia.text,
                llmClass: widget.config.llmClass,
                model: widget.config.model,
                llmTemperature: widget.config.llmTemperature,
                transcriptionProvider: widget.config.transcriptionProvider,
                transcriptionModel: widget.config.transcriptionModel,
                visionProvider: widget.config.visionProvider,
                visionModel: widget.config.visionModel,
                embeddingsClass: widget.config.embeddingsClass,
                embeddingsModel: widget.config.embeddingsModel,
                chunkSize: widget.config.chunkSize,
                chunkOverlap: widget.config.chunkOverlap,
                similarityThreshold: widget.config.similarityThreshold,
                vectorDistanceThreshold: widget.config.vectorDistanceThreshold,
                apiKeys: widget.config.apiKeys,
              )),
            ),
          ],
        ),
      ),
    );
  }
}
