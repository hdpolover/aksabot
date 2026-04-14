class FirmwareRelease {
  final String id;
  final String version;
  final String sha256;
  final int size;
  final String? changelog;
  final DateTime createdAt;

  const FirmwareRelease({
    required this.id,
    required this.version,
    required this.sha256,
    required this.size,
    this.changelog,
    required this.createdAt,
  });
}
