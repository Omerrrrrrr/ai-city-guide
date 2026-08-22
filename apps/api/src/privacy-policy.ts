// Served at GET /privacy -- the URL App Store Connect requires. Plain HTML,
// not a route that needs auth/JSON, so it lives as its own static string
// rather than templated through any of the app's other response shapes.
export const PRIVACY_POLICY_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Piri — Privacy Policy</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 720px; margin: 0 auto; padding: 40px 20px 80px; line-height: 1.6; color: #1c2436; background: #fcf9f0; }
  h1 { font-size: 1.75rem; margin-bottom: 4px; }
  .updated { color: #6b7280; font-size: 0.9rem; margin-bottom: 32px; }
  h2 { font-size: 1.2rem; margin-top: 36px; }
  ul { padding-left: 20px; }
  li { margin-bottom: 6px; }
  a { color: #7d5714; }
  .intro { color: #374151; }
  footer { margin-top: 48px; padding-top: 20px; border-top: 1px solid #ded0a8; color: #6b7280; font-size: 0.85rem; }
</style>
</head>
<body>
  <h1>Piri — Privacy Policy</h1>
  <p class="updated">Last updated: August 19, 2026</p>

  <p class="intro">
    Piri ("the app", "we", "us") is a travel and points-of-interest discovery app.
    This policy explains what information Piri collects, how it is used, and who
    it may be shared with. It applies to everyone who uses the Piri iOS app.
  </p>

  <h2>Information you provide to us</h2>
  <ul>
    <li><strong>Account information</strong>: email address and password (stored as a
      one-way hash, never in plain text), or your Apple ID identifier if you sign in
      with Apple. An optional display name and username.</li>
    <li><strong>Profile preferences</strong>: things you choose to tell us to
      personalize recommendations — interests, profession, budget level, group type,
      travel pace, and dietary needs (e.g. halal, kosher, vegetarian). All optional.</li>
    <li><strong>Content you submit</strong>: photos and captions you upload for a
      place, reports you file about other users' content, and users you choose to
      block.</li>
    <li><strong>Social preferences</strong>: if you choose to add friends or appear on
      the public leaderboard, your username, XP, and trip statistics may become
      visible to other users — this is off by default and controlled entirely by you
      in Settings.</li>
  </ul>

  <h2>Information collected automatically</h2>
  <ul>
    <li><strong>Location</strong>: used, with your permission, to search nearby places,
      show weather, and calculate directions. Sent with each relevant request; Piri
      does not build or store a history of your past locations.</li>
    <li><strong>Photos you scan or ask about</strong>: when you use the camera-based
      "identify this place" feature or ask a question about a place, the photo or
      question is sent to our AI providers to generate a response. It is not stored
      after the request completes unless you separately choose to submit it as a
      place photo.</li>
    <li><strong>Device push token</strong>: if you enable notifications, an Apple Push
      Notification token tied to your device.</li>
    <li><strong>Crash and error diagnostics</strong>: technical error reports (via
      Sentry) to help us fix bugs. These do not include your account password or
      photo content.</li>
  </ul>

  <h2>How we use your information</h2>
  <ul>
    <li>To operate core features: search, AI-generated place descriptions, directions,
      weather, saved places and trips, and account sync across your devices.</li>
    <li>To personalize recommendations based on the profile preferences you provide.</li>
    <li>To moderate user-submitted content and enforce our reporting/blocking system.</li>
    <li>To diagnose and fix technical problems.</li>
    <li>To enforce usage limits on premium features.</li>
  </ul>
  <p>We do not sell your personal information, and we do not use your data for
    third-party advertising.</p>

  <h2>Third-party services we use</h2>
  <p>Certain features send limited, request-specific data to these providers so they
    can generate a result. Each is used only for the purpose described:</p>
  <ul>
    <li><strong>OpenAI</strong> — AI-generated place descriptions, chat answers,
      photo identification, and pre-publication moderation of submitted photos.</li>
    <li><strong>Google (Generative AI, Places)</strong> — AI responses and, for
      paying users, richer place details.</li>
    <li><strong>OpenRouter</strong> — routes some AI requests to the model
      currently configured for that feature.</li>
    <li><strong>Tripadvisor, Unsplash, OpenWeather, OpenRouteService</strong> —
      ratings/reviews, photos, weather, and turn-by-turn directions respectively.</li>
    <li><strong>Sentry</strong> — crash and error diagnostics.</li>
    <li><strong>Apple</strong> — Sign in with Apple and push notification delivery.</li>
  </ul>

  <h2>Where your data is stored</h2>
  <p>Account and app data is stored in a Postgres database hosted in Frankfurt,
    Germany. Photos you submit are stored in Cloudflare R2 object storage.</p>

  <h2>Your rights</h2>
  <p>You can request access to, correction of, or deletion of your account and
    associated data at any time by contacting us at the address below. Deleting your
    account removes your profile, saved places, trips, and submitted content from our
    systems, except where we are required to retain records (e.g. content already
    reported for moderation review).</p>

  <h2>Children's privacy</h2>
  <p>Piri is not directed at children under 13, and we do not knowingly collect
    information from children under 13.</p>

  <h2>Content moderation, reporting, and blocking</h2>
  <p>User-submitted photos are automatically screened before becoming visible to
    other users. You can report content you believe is inappropriate, and block
    users whose content you no longer want to see — reported content that receives
    multiple reports is automatically hidden pending review.</p>

  <h2>Changes to this policy</h2>
  <p>If we make material changes to this policy, we will update the "Last updated"
    date above.</p>

  <h2>Contact</h2>
  <p>Questions about this policy or your data can be sent to
    <a href="mailto:privacy@getpiri.com">privacy@getpiri.com</a>.</p>

  <footer>Piri</footer>
</body>
</html>
`;
