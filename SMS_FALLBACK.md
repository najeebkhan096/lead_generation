# SMS fallback for outreach (US leads) and the test page

WhatsApp (Meta) blocks marketing templates to US phone numbers (Twilio error
**63049**), so US leads are reached by SMS instead, with a link to continue on
WhatsApp. Other countries keep using the WhatsApp template. See
[TWILIO_INTEGRATION.md](TWILIO_INTEGRATION.md) for the rest of the Twilio setup.

## How a template is routed

| Lead number | `channel: auto` (default) | Override |
| --- | --- | --- |
| US (+1, 10 digits) | **SMS** (MMS with the image) | `whatsapp` forces WhatsApp (likely blocked) |
| Anything else | **WhatsApp** template | `sms` forces SMS (see limits below) |

- Routing lives in `functions/src/twilioChat/validation.js`
  (`isUsNumber`, `channelForTemplate`, `buildSmsBody`) and
  `messageService.js` (`sendOutbound`, `dispatchToTwilio`, `retryOutbound`).
- The SMS body is the template text plus
  `Prefer WhatsApp? Reply directly or tap here to chat: https://wa.me/<number>`.
  The link is omitted if `TWILIO_WHATSAPP_NUMBER` is not set.
- Every outbound message document has `channel: 'whatsapp' | 'sms'`. `type`
  is unchanged (`template`, `text`, ...).
- Retrying a failed message keeps its channel, so an old US message that
  failed with 63049 is resent by SMS.
- An inbound **SMS** reply does not open the 24-hour WhatsApp window (only
  `whatsapp:` senders do), so free-form WhatsApp replies stay locked until they
  message you on WhatsApp.
- `+1` also covers Canada and the Caribbean. They are sent by SMS too.

## Configuration (`functions/.env`, gitignored)

```
TWILIO_ACCOUNT_SID=...
TWILIO_AUTH_TOKEN=...
TWILIO_MESSAGING_SERVICE_SID=...      # WhatsApp sender
TWILIO_TEMPLATE_CONTENT_SID=...
TWILIO_PHONE_NUMBER=+14342049677      # SMS sender (must be a Twilio number)
TWILIO_WHATSAPP_NUMBER=+14342049677   # number the wa.me link points to
```

Deploy with `firebase deploy --only functions`. The trailing
"could not set up cleanup policy" message is harmless
(`firebase functions:artifacts:setpolicy` silences it).

If `TWILIO_PHONE_NUMBER` is missing, SMS sends fail with
`TWILIO_NOT_CONFIGURED`.

## Test page (mobile)

Outreach tab → **⋮** → **Send a test message**
(`mobile/lib/features/twilio_outreach/pages/send_test_page.dart`).

1. Enter any number in international format, e.g. `+971501234567`.
2. **Send SMS** sends your text by SMS (any country; backend action `sms`).
3. **Send template** sends the outreach template with an image on the chosen
   channel (Auto / SMS / WhatsApp).
4. Live status of the latest messages is shown under the buttons.

## Errors and what they mean

| Shown message | Code | Cause / fix |
| --- | --- | --- |
| WhatsApp marketing is blocked for US (+1) numbers by Meta... | 63049 | Meta policy. Use SMS for US leads. |
| Twilio cannot send SMS from this number to that country... | 21612 | The sender cannot reach that destination (e.g. a US number to Qatar). Send on WhatsApp, enable the country in Twilio Geo Permissions, or use a sender that supports it. |
| SMS to this country is not enabled in Twilio Geo Permissions | 21408 | Enable the country: Twilio Console → Messaging → Settings → Geo Permissions. |
| US SMS blocked: the sender number has no approved 10DLC registration | 30034 | Register the brand and campaign (A2P 10DLC). |
| The carrier filtered this SMS | 30007 | Content or sender reputation. Review the text and campaign. |
| The toll-free number is not verified for SMS yet | 30032 | Complete toll-free verification. |
| That phone number is not valid / cannot receive SMS | 21211 / 21614 | Check the number and its country code. |

## Known limits

- A US number is only reliably able to SMS US/Canada recipients. Many other
  countries need a registered alphanumeric sender ID or block foreign long
  codes. Use WhatsApp for those leads.
- Twilio trial accounts can only message verified numbers.
- The `wa.me` link only works if the number has a WhatsApp account (a WhatsApp
  Business sender in Twilio, or a normal WhatsApp account).
- Cold SMS needs 10DLC approval, which can be hard to get for unsolicited sales
  messages.

## Tests

```
cd functions && npm test
```

Covers US detection, channel selection, the SMS body and the 63049 text.
