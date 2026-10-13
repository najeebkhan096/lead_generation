import 'dart:async';
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'web_image_picker.dart';

const _maxBytes = 5 * 1024 * 1024;
const _types = ['image/jpeg', 'image/png'];

Future<PickedImage?> pickWebImage() {
  final done = Completer<PickedImage?>();
  final input = html.FileUploadInputElement()..accept = _types.join(',');

  void finish(PickedImage? image) {
    if (!done.isCompleted) done.complete(image);
  }

  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return finish(null);
    if (!_types.contains(file.type)) {
      return done.completeError(const ImagePickException('Choose a JPEG or PNG image.'));
    }
    if (file.size > _maxBytes) {
      return done.completeError(const ImagePickException('The image is larger than 5 MB.'));
    }
    final reader = html.FileReader()..readAsArrayBuffer(file);
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      final bytes = result is Uint8List ? result : (result as ByteBuffer).asUint8List();
      finish(PickedImage(bytes: bytes, mimeType: file.type, name: file.name));
    });
  });
  input.on['cancel'].first.then((_) => finish(null));
  input.click();
  return done.future;
}
