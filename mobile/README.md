# Lead Outreach (Flutter mobile)

Browse businesses saved to **Firebase Firestore** by category. Open **Google Maps** or **WhatsApp** for each lead.

## Setup

Firebase is already wired to project `whatsapplead-a8d9a`:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

Firestore rules allow read on `leads` (writes stay on the backend Admin SDK).

## Run

```bash
cd mobile
flutter pub get
flutter run
```

Pick an Android emulator/device or iPhone simulator/device.

## Flow

1. Use the LeadFinder web/backend search and tap **Save to Firebase**
2. Open this mobile app
3. Choose a category (Dentist, Salon, … or All)
4. Tap **Maps** or **WhatsApp** on a business card

## Notes

- Empty lists mean no leads have been saved for that category yet
- WhatsApp must be installed on the device for the chat button to open the app
