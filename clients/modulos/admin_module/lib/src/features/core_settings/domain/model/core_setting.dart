class CoreSetting {
  final String key;
  final String value;
  final bool encrypted;
  final String description;

  const CoreSetting({
    required this.key,
    required this.value,
    required this.encrypted,
    required this.description,
  });
}
