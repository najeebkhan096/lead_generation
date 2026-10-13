import 'dart:typed_data';

import 'web_image_picker_stub.dart'
    if (dart.library.html) 'web_image_picker_web.dart' as impl;

/// An image chosen in the browser's file dialog.
class PickedImage {
  const PickedImage({required this.bytes, required this.mimeType, required this.name});

  final Uint8List bytes;

  /// `image/jpeg` or `image/png`.
  final String mimeType;
  final String name;
}

/// Why a chosen file was not usable (wrong type / too large).
class ImagePickException implements Exception {
  const ImagePickException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef ImagePicker = Future<PickedImage?> Function();

/// Opens the browser's file dialog for a JPEG or PNG (max 5 MB). Returns null
/// when cancelled, and also on platforms without a browser; throws
/// [ImagePickException] for an unusable file.
Future<PickedImage?> pickWebImage() => impl.pickWebImage();
