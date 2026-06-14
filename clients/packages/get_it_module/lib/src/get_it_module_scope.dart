import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'get_it_module_base.dart';
import 'injector.dart';

/// Widget interno que conecta o ciclo de vida da tela ao escopo do GetIt.
///
/// Em [initState] empilha um novo escopo nomeado e registra os binds da
/// feature. Em [dispose] descarta exatamente esse escopo pelo nome, chamando
/// o `dispose` de cada dependência local registrada.
///
/// O nome do escopo é gerado por **montagem** (a partir do `identityHashCode`
/// deste State), garantindo unicidade mesmo quando o roteador reaproveita a
/// mesma instância do módulo entre navegações ou empilha a mesma rota.
///
/// É construído pelo package via [GetItModule.toRoute]; os módulos de feature
/// nunca o instanciam diretamente.
class GetItModuleScope extends StatefulWidget {
  final GetItModule module;

  const GetItModuleScope({super.key, required this.module});

  @override
  State<GetItModuleScope> createState() => _GetItModuleScopeState();
}

class _GetItModuleScopeState extends State<GetItModuleScope> {
  final GetIt _getIt = GetIt.instance;

  /// Único por montagem deste widget.
  late final String _scopeName =
      '${widget.module.runtimeType}#${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    _getIt.pushNewScope(scopeName: _scopeName);
    widget.module.binds(Injector(_getIt));
  }

  @override
  void dispose() {
    if (_getIt.hasScope(_scopeName)) {
      _getIt.dropScope(_scopeName);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.module.page;
}
