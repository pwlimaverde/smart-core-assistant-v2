import 'package:dependencies_module/dependencies_module.dart' hide CoreSetting;

import '../../domain/model/core_setting.dart';
import '../controllers/core_settings_controller.dart';
import '../widgets/admin_drawer.dart';

class CoreSettingsPage extends StatefulWidget {
  const CoreSettingsPage({super.key});

  @override
  State<CoreSettingsPage> createState() => _CoreSettingsPageState();
}

class _CoreSettingsPageState extends State<CoreSettingsPage> {
  late final CoreSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<CoreSettingsController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configurações Globais',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchSettings,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Configurações do Sistema',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nova Configuração'),
                  onPressed: () => _showEditDialog(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<CoreSettingsController, List<CoreSetting>>(
                controller: _controller,
                onSuccess: (context, settings) {
                  if (settings.isEmpty) {
                    return const Center(
                      child: Text('Nenhuma configuração cadastrada.'),
                    );
                  }
                  return _buildSettingsList(settings);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsList(List<CoreSetting> settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ListView.separated(
      itemCount: settings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final setting = settings[index];
        return AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          setting.key,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        if (setting.encrypted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock, size: 12, color: Colors.amber),
                                SizedBox(width: 4),
                                Text(
                                  'Cifrado',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      setting.description.isNotEmpty
                          ? setting.description
                          : 'Sem descrição cadastrada.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        setting.value,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'Editar',
                    onPressed: () => _showEditDialog(context, setting),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Excluir',
                    onPressed: () => _confirmDelete(context, setting.key),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, [CoreSetting? setting]) {
    final keyController = TextEditingController(text: setting?.key);
    final valController = TextEditingController(text: setting?.value);
    final descController = TextEditingController(text: setting?.description);
    bool encrypted = setting?.encrypted ?? false;
    final isNew = setting == null;
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateContext, setStateDialog) {
            return AlertDialog(
              title: Text(isNew ? 'Nova Configuração Global' : 'Editar Configuração'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppTextField(
                        label: 'Chave (Key)',
                        hint: 'ex: OPENAI_DEFAULT_MODEL',
                        controller: keyController,
                        // Não permite editar a chave de uma config existente
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Valor (Value)',
                        hint: 'Informe o valor',
                        controller: valController,
                        obscureText: encrypted,
                        obscureToggle: encrypted,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Descrição',
                        hint: 'Explicação sobre a utilidade desta configuração',
                        controller: descController,
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Criptografar/Cifrar valor no banco'),
                        subtitle: const Text('Recomendado para senhas e API Keys'),
                        value: encrypted,
                        onChanged: isNew
                            ? (val) => setStateDialog(() => encrypted = val ?? false)
                            : null, // Não permite alterar criptografia de chave existente
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                PrimaryButton(
                  label: 'Salvar',
                  expand: false,
                  onPressed: () async {
                    final key = keyController.text.trim();
                    final value = valController.text.trim();
                    final description = descController.text.trim();
                    
                    if (key.isBlank()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('A chave não pode ser vazia.')),
                      );
                      return;
                    }

                    final res = await _controller.upsertSetting(
                      key: key,
                      value: value,
                      encrypted: encrypted,
                      description: description,
                    );
                    
                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      if (res is ErrorReturn) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao salvar: ${(res as ErrorReturn).result.message}')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Configuração salva com sucesso.')),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, String key) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza de que deseja excluir a chave "$key"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final res = await _controller.deleteSetting(key);
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  if (res is ErrorReturn) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao excluir: ${(res as ErrorReturn).result.message}')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Configuração excluída com sucesso.')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
extension on String {
  bool isBlank() => trim().isEmpty;
}
