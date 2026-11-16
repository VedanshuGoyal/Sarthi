import 'package:flutter/foundation.dart';

import '../../../core/config/app_build.dart';
import '../data/app_config_repository.dart';

/// Decides whether this build must be replaced before the app can be used.
///
/// Two things close the gate, and nothing reopens it (the fix is installing
/// a new build, which restarts the app):
///
///  * the backend answering any request 426 `update_required` — the
///    backend client calls [require];
///  * `GET /app/config` at startup ([check]) listing a `minBuild` above
///    this build.
class UpdateGateViewModel extends ChangeNotifier {
  UpdateGateViewModel({
    required this._repository,
    this._build = AppBuild.number,
  });

  final AppConfigRepository _repository;
  final int _build;

  String? _downloadUrl;
  bool _checked = false;
  bool _disposed = false;

  /// Whether the update screen should replace the app.
  bool get updateRequired => _downloadUrl != null;

  /// Where to get the update.
  String get downloadUrl => _downloadUrl ?? AppBuild.defaultDownloadUrl;

  /// Reads the backend's minimum build, once. Never throws and never holds
  /// up the app: if the backend can't be reached, a 426 will still close
  /// the gate on the first real request.
  Future<void> check() async {
    if (_checked) return;
    _checked = true;
    try {
      final release = await _repository.fetch();
      if (release != null && release.requiresUpdate(_build)) {
        require(release.downloadUrl);
      }
    } catch (_) {
      // Offline, or an older backend without /app/config: nothing to enforce.
    }
  }

  /// Closes the gate; [url] is where the backend says to download from.
  void require([String? url]) {
    final next = (url != null && url.isNotEmpty)
        ? url
        : (_downloadUrl ?? AppBuild.defaultDownloadUrl);
    if (next == _downloadUrl) return;
    _downloadUrl = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
