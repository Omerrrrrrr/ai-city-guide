// Served at GET /support -- the Support URL App Store Connect requires for
// the app's first version submission. Plain HTML, same pattern as
// `privacy-policy.ts`.
export const SUPPORT_PAGE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Piri — Support</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 720px; margin: 0 auto; padding: 40px 20px 80px; line-height: 1.6; color: #1c2436; background: #fcf9f0; }
  h1 { font-size: 1.75rem; margin-bottom: 4px; }
  .intro { color: #374151; }
  h2 { font-size: 1.2rem; margin-top: 36px; }
  ul { padding-left: 20px; }
  li { margin-bottom: 6px; }
  a { color: #7d5714; }
  footer { margin-top: 48px; padding-top: 20px; border-top: 1px solid #ded0a8; color: #6b7280; font-size: 0.85rem; }
</style>
</head>
<body>
  <h1>Piri — Support</h1>

  <p class="intro">
    Need help with Piri, or found a bug? Reach out and we'll get back to you.
  </p>

  <h2>Contact</h2>
  <ul>
    <li>Email: <a href="mailto:support@getpiri.com">support@getpiri.com</a></li>
  </ul>

  <h2>Common questions</h2>
  <ul>
    <li>Manage or cancel a subscription: iOS Settings &rarr; your name &rarr; Subscriptions.</li>
    <li>Restore a purchase: open Piri &rarr; Profile &rarr; Restore purchases.</li>
  </ul>

  <footer>
    <a href="/privacy">Privacy Policy</a>
  </footer>
</body>
</html>`;
