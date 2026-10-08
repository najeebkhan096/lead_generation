import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// =============================================================================
// TEMPLATE HEADER IMAGE: pick (gallery/camera) -> upload to Firebase -> https URL
// =============================================================================
/// Asks the user for a gallery/camera image, uploads it to Firebase Storage and
/// returns its download URL (what Twilio needs for the template's image
/// header; the backend strips the template's fixed prefix before sending).
/// Returns null if the user cancels; throws on upload failure.
Future<String?> pickAndUploadTemplateImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    imageQuality: 85,
  );
  if (picked == null) return null;
  debugPrint('[Outreach] picked template image: ${picked.path}');

  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
  final ref = FirebaseStorage.instance
      .ref('outreach_images/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
  await ref.putFile(File(picked.path), SettableMetadata(contentType: 'image/jpeg'));
  final url = await ref.getDownloadURL();
  debugPrint('[Outreach] uploaded template image');
  return url;
}
