import 'package:get_it/get_it.dart';

/// Resolve uma dependência registrada, buscando do escopo de feature ativo até
/// o escopo-base global.
///
/// É a forma padrão de obter Cubits e serviços na UI, mantendo as telas
/// desacopladas da API direta do GetIt.
T inject<T extends Object>() => GetIt.instance.get<T>();
