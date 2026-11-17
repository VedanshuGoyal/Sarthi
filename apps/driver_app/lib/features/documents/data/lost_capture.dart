import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Hands back the path of a photo the camera took while Android had killed
/// the app, or null when there is none.
typedef LostCaptureSource = Future<String?> Function();

/// The camera is a separate activity, and a phone short on memory reclaims
/// the app behind it. image_picker keeps the photo taken meanwhile and
/// returns it once, on the next launch; without asking, it is lost and the
/// driver is sent round the same loop. The selfie is the only photo the app
/// takes with the camera.
Future<String?> retrieveLostCameraPhoto() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final lost = await ImagePicker().retrieveLostData();
    return lost.file?.path;
  } catch (_) {
    return null;
  }
}
