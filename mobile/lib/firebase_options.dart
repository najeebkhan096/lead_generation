// File generated for Lead Mobile — do not commit secrets to public repos carelessly.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for lead_mobile.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBr1QVIIuO0zeOYoAFXYYrF4d44oM62LF8',
    appId: '1:3988909442:android:4083700c18ceab983f339b',
    messagingSenderId: '3988909442',
    projectId: 'whatsapplead-a8d9a',
    storageBucket: 'whatsapplead-a8d9a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCfiHNqsm0bGcwN0Ln5ljdLkR2bQFKAGCI',
    appId: '1:3988909442:ios:152f89b94b6f3f163f339b',
    messagingSenderId: '3988909442',
    projectId: 'whatsapplead-a8d9a',
    storageBucket: 'whatsapplead-a8d9a.firebasestorage.app',
    iosBundleId: 'com.example.whatsLead',
  );
}
