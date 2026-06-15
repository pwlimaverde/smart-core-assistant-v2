// Reexporta o go_router para que as features tenham context.go/push,
// GoRoute e GoRouterState sem importar o package diretamente.
export 'package:go_router/go_router.dart';

export 'src/module_route.dart';
export 'src/boot_state.dart';
export 'src/app_router.dart';
