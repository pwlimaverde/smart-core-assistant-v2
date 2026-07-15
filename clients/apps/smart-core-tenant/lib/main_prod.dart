import 'package:app_config/app_config.dart';

import 'bootstrap.dart';

void main() => bootstrap(
  const AppConfig(
    flavor: AppFlavor.prod,
    apiEndpoint: String.fromEnvironment('SMARTCORE_API_ENDPOINT'),
    enableLogging: false,
  ),
);
