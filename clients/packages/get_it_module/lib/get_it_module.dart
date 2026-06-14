// Superfície pública mínima: contratos + fachada + helper de resolução.
export 'src/app_module.dart'; // AppModule, BootStage, BootTask, installModules, collectRoutes, runBootTasks, bootModules
export 'src/get_it_module_base.dart'; // GetItModule (rota)
export 'src/injector.dart';
export 'src/inject.dart';

// get_it_module_scope.dart NÃO é exportado: é detalhe interno do package.
