import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/subscription.dart';
import '../services/admin_service.dart';

final class ListSubscriptionsUsecase {
  final AdminService _service;

  const ListSubscriptionsUsecase({required this._service});

  Future<ReturnSuccessOrError<List<Subscription>>> call() => _service.listSubscriptions();
}
