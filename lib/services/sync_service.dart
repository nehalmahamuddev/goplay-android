import '../models/category.dart';
import 'catalog/catalog_repository.dart';

/// Backward-compatible sync facade delegating catalog synchronization and
/// M3U playlist updates to [CatalogRepository].
class SyncService {
  SyncService(
    this._repository, {
    void Function()? onInvalidateChannels,
  }) : _onInvalidateChannels = onInvalidateChannels;

  final CatalogRepository _repository;
  final void Function()? _onInvalidateChannels;

  Future<void> sync({bool forceM3uRefresh = false}) =>
      _repository.sync(forceM3uRefresh: forceM3uRefresh);

  Future<bool> refreshM3uDirectly({
    bool force = false,
    Duration? minInterval,
  }) =>
      _repository.refreshM3uDirectly(force: force, minInterval: minInterval);

  Future<bool> refreshM3uCategoryIfDue(
    Category category, {
    bool force = false,
    Duration cooldown = const Duration(seconds: 15),
  }) =>
      _repository.refreshM3uCategoryIfDue(
        category,
        force: force,
        cooldown: cooldown,
      );

  Future<bool> checkForCategoryChangesIfDue({
    Duration cooldown = const Duration(minutes: 2),
  }) =>
      _repository.checkForCategoryChangesIfDue(cooldown: cooldown);

  void invalidateChannelProviders() {
    _onInvalidateChannels?.call();
  }
}
