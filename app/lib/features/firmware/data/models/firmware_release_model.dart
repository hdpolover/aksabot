import '../../domain/entities/firmware_release.dart';

class FirmwareReleaseModel extends FirmwareRelease {
  const FirmwareReleaseModel({
    required super.id,
    required super.version,
    required super.sha256,
    required super.size,
    super.changelog,
    required super.createdAt,
  });

  factory FirmwareReleaseModel.fromJson(Map<String, dynamic> json) {
    return FirmwareReleaseModel(
      id: json['id'] as String,
      version: json['version'] as String,
      sha256: json['sha256'] as String,
      size: json['size'] as int,
      changelog: json['changelog'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
