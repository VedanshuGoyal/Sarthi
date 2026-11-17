/// One app's place in the backend's client compatibility contract, from
/// `GET /app/config`.
class AppRelease {
  const AppRelease({
    required this.minBuild,
    required this.latestBuild,
    required this.downloadUrl,
  });

  /// Reads an `apps.<app>` entry. Missing numbers read as 0 (nothing
  /// enforced); a missing URL as empty.
  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    minBuild: (json['minBuild'] as num?)?.toInt() ?? 0,
    latestBuild: (json['latestBuild'] as num?)?.toInt() ?? 0,
    downloadUrl: json['downloadUrl'] as String? ?? '',
  );

  /// The oldest build the backend still serves.
  final int minBuild;

  /// The newest published build.
  final int latestBuild;

  /// Where the APKs are published.
  final String downloadUrl;

  /// Whether [build] is too old to use. Build 0 (a debug run) never is,
  /// matching the backend.
  bool requiresUpdate(int build) => build > 0 && build < minBuild;
}
