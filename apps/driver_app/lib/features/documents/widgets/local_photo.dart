import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Renders a photo the driver just picked, from the `XFile.path` handed back
/// by `image_picker`.
///
/// On web that path is a `blob:` URL and `Image.file` is unsupported, so the
/// platform split has to happen here rather than at the call site.
class LocalPhoto extends StatelessWidget {
  const LocalPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) =>
      kIsWeb ? Image.network(path, fit: fit) : Image.file(File(path), fit: fit);
}
