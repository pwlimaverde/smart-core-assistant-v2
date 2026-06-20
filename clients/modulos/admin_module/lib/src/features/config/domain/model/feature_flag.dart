final class FeatureFlagOverride {
  final String tenantId;
  final bool enabled;

  const FeatureFlagOverride({
    required this.tenantId,
    required this.enabled,
  });
}

final class FeatureFlag {
  final String key;
  final String description;
  final bool enabledGlobally;
  final List<FeatureFlagOverride> overrides;

  const FeatureFlag({
    required this.key,
    required this.description,
    required this.enabledGlobally,
    required this.overrides,
  });
}
