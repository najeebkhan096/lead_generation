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
/// Shows a preview and asks for confirmation before anything is uploaded, so
/// a wrong pick never reaches the contact. [recipient] names who gets it.
/// Returns null if the user cancels; throws on upload failure.
Future<String?> pickAndUploadTemplateImage(BuildContext context, {String? recipient}) async {
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
  if (!context.mounted) return null;
  final confirmed = await _confirmSend(context, File(picked.path), recipient);
  if (confirmed != true) return null;

  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
  final ref = FirebaseStorage.instance
      .ref('outreach_images/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
  await ref.putFile(File(picked.path), SettableMetadata(contentType: 'image/jpeg'));
  final url = await ref.getDownloadURL();
  debugPrint('[Outreach] uploaded template image');
  return url;
}

Future<bool?> _confirmSend(BuildContext context, File image, String? recipient) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send this image?', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              recipient == null || recipient.isEmpty
                  ? 'It will be sent with the outreach template.'
                  : 'It will be sent to $recipient with the outreach template.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(image, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
}
