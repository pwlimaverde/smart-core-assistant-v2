import 'package:flutter_web_plugins/url_strategy.dart';

/// Aplica a path URL strategy (URLs limpas sob `/v2/tenant/`, sem `#`).
void usePlatformUrlStrategy() => usePathUrlStrategy();
