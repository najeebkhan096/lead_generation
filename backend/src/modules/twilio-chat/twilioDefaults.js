/**
 * Twilio account values now come only from environment variables
 * (TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_MESSAGING_SERVICE_SID,
 * TWILIO_TEMPLATE_CONTENT_SID). Never hard-code them here.
 */
export const TWILIO_DEFAULTS = {
  accountSid: '',
  authToken: '',
  messagingServiceSid: '',
  templateContentSid: '',
};
