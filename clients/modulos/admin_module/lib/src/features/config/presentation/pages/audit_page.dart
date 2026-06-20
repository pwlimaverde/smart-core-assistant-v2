import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dependencies_module/dependencies_module.dart' hide Tenant, AuditLogEntry;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;

import '../../domain/model/audit_log_entry.dart';
import '../../domain/model/tenant.dart';
import '../controllers/audit_controller.dart';
import '../widgets/admin_drawer.dart';

class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  late final AuditController _controller;
  List<Tenant> _tenants = [];
  String? _selectedTenantId;
  String? _selectedEventType;
  bool _isExporting = false;

  final List<Map<String, String>> _eventTypes = const [
    {'label': 'Todos os Eventos', 'value': ''},
    {'label': 'Login Efetuado', 'value': 'auth_login'},
    {'label': 'Acesso Negado', 'value': 'auth_access_denied'},
    {'label': 'Configuração Alterada', 'value': 'config_changed'},
    {'label': 'Tenant Modificado', 'value': 'tenant_modified'},
    {'label': 'Faturamento Modificado', 'value': 'billing_modified'},
  ];

  @override
  void initState() {
    super.initState();
    _controller = inject<AuditController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchAuditLogs();
      _loadFilterData();
    });
  }

  Future<void> _loadFilterData() async {
    final res = await _controller.getTenants();
    if (res is SuccessReturn<List<Tenant>> && mounted) {
      setState(() {
        _tenants = res.result;
      });
    }
  }

  void _applyFilters() {
    _controller.fetchAuditLogs(
      tenantId: _selectedTenantId,
      eventType: _selectedEventType,
    );
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    final res = await _controller.exportTenantsCsv();
    setState(() => _isExporting = false);

    if (!mounted) return;

    if (res is SuccessReturn<List<int>>) {
      _downloadFile(res.result, 'tenants_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportação concluída com sucesso!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar CSV: ${(res as ErrorReturn).result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _downloadFile(List<int> bytes, String filename) {
    if (!kIsWeb) return;
    final blob = web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    web.document.body?.appendChild(anchor);
    anchor.click();
    web.document.body?.removeChild(anchor);
    web.URL.revokeObjectURL(url);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Logs de Auditoria & Segurança',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _applyFilters,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rastreabilidade & Auditoria',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monitore mutações de dados críticos e tentativas de acesso aos recursos sensíveis.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(_isExporting ? 'Exportando...' : 'Exportar Tenants (CSV)'),
                  onPressed: _isExporting ? null : _exportCsv,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Painel de Filtros
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _selectedTenantId,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por Tenant / Cliente',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos os Tenants'),
                        ),
                        ..._tenants.map((t) => DropdownMenuItem<String?>(
                              value: t.id,
                              child: Text(t.name),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedTenantId = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _selectedEventType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Evento',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _eventTypes.map((e) => DropdownMenuItem<String?>(
                            value: e['value'],
                            child: Text(e['label']!),
                          )).toList(),
                      onChanged: (val) {
                        setState(() => _selectedEventType = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _applyFilters,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: const Text('Filtrar'),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Listagem de Logs
            Expanded(
              child: ViewStateBuilder<AuditController, List<AuditLogEntry>>(
                controller: _controller,
                onSuccess: (context, logs) {
                  if (logs.isEmpty) {
                    return const Center(
                      child: Text('Nenhum log de auditoria encontrado para o filtro aplicado.'),
                    );
                  }
                  return _buildAuditTable(logs);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditTable(List<AuditLogEntry> logs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 100),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                isDark ? Colors.grey[900] : Colors.grey[100],
              ),
              columns: const [
                DataColumn(label: Text('Data / Hora', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Evento', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Ator', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Descrição', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('IP / Dispositivo', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: logs.map((log) {
                return DataRow(
                  cells: [
                    DataCell(Text(
                      _formatDate(log.createdAt),
                      style: const TextStyle(fontSize: 13),
                    )),
                    DataCell(_buildEventBadge(log.eventType)),
                    DataCell(Text(log.actor, style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Text(
                          log.description,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                    DataCell(
                      Tooltip(
                        message: log.userAgent,
                        child: Text(
                          '${log.ipAddress}\n${_truncateUserAgent(log.userAgent)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min:$s';
  }

  Widget _buildEventBadge(String eventType) {
    Color color;
    String label;

    switch (eventType.toLowerCase()) {
      case 'auth_login':
        color = Colors.blue;
        label = 'LOGIN';
        break;
      case 'auth_access_denied':
        color = Colors.red;
        label = 'NEGADO';
        break;
      case 'config_changed':
        color = Colors.orange;
        label = 'CONFIG';
        break;
      case 'tenant_modified':
        color = Colors.teal;
        label = 'TENANT';
        break;
      case 'billing_modified':
        color = Colors.purple;
        label = 'FATURAMENTO';
        break;
      default:
        color = Colors.grey;
        label = eventType.toUpperCase();
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _truncateUserAgent(String ua) {
    if (ua.length > 30) {
      return '${ua.substring(0, 27)}...';
    }
    return ua;
  }
}
