# AI City Guide

AI City Guide is a Kristiansand-focused city guide with an Expo mobile client and a Fastify API backed by Postgres.

## Workspace

- `apps/api`: Fastify API, Drizzle schema, seed data, optional AI recommendation route
- `mobile`: Expo app with home, explore, map, saved, settings, and AI screens
- `infrastructure/db`: local Postgres via Docker Compose

## Local Setup

### 1. Start Postgres

```bash
docker compose -f infrastructure/db/docker-compose.yml up -d
```

### 2. Start the API

```bash
cd apps/api
cp .env.example .env
npm install
npm run seed
npm run dev
```

Notes:

- Default API port is `4000`
- `OPENAI_API_KEY` or `OPENROUTER_API_KEY` is optional until you want `/places/recommend` to work
- Default OpenAI model is `gpt-4o-mini`
- Default OpenRouter model is `anthropic/claude-sonnet-4.5`
- If both AI providers are configured, `AI_PROVIDER=openai` or `AI_PROVIDER=openrouter` can force the backend choice
- `GOOGLE_MAPS_API_KEY` is optional until you want Google-based opening-hours preview in `Settings -> Open Hours Review`

### 3. Start the Mobile App

```bash
cd mobile
cp .env.example .env
npm install
npm run start
```

If you are testing on a physical device, set `EXPO_PUBLIC_API_URL` in `mobile/.env` to your machine's LAN address, for example `http://192.168.1.20:4000`.

## Validation

### API

```bash
cd apps/api
npm run typecheck
npm run build
npm run test
```

### Mobile

```bash
cd mobile
npm run typecheck
npm run lint
```

## Current Status

- Places list, place detail, search, filters, and nearby suggestions are wired to the API
- Saved favorites and plan state are persisted locally on device
- Map view reads live coordinates from the backend
- AI screen is connected and becomes active once OpenAI or OpenRouter is configured
- Verified place photos can be discovered from Wikimedia Commons through a candidate review flow
- Verified opening hours can be edited in-app and optionally prefetched from Google Places for review

## Hours Review Workflow

The mobile app includes a safe hours workflow under `Settings -> Open Hours Review`:

1. Open a place in Hours Review
2. Optionally press `Fetch Google Preview`
3. Inspect the returned match, weekday text, and closure status
4. Press `Use This Preview` to prefill the form
5. Review the data and press `Save Hours`

Notes:

- Google preview never auto-publishes. It only fills the form for manual review.
- Without `GOOGLE_MAPS_API_KEY`, the Hours Review screen still works for manual verified entry.
- Once saved, verified hours replace `Likely open now` with real `Open now / Closed now` in the app.

## Image Review Workflow

The backend now supports a safe image pipeline:

1. Discover candidate images from Wikimedia Commons
2. Review the candidates in the terminal
3. Approve the best candidate
4. Apply the approved image to the live place record

Example:

```bash
cd apps/api
npm run images:discover -- --place=hamresanden --limit=5
npm run images:list -- --place=hamresanden
npm run images:approve -- --candidate=wikimedia:hamresanden:YOUR_ID
npm run images:apply -- --candidate=wikimedia:hamresanden:YOUR_ID
```

Useful commands:

```bash
# Discover candidates for every place that still has an unverified image
npm run images:discover

# Discover for one place only
npm run images:discover -- --place=posebyen --limit=5

# Include places that already have a verified image
npm run images:discover -- --place=posebyen --include-verified

# List candidates
npm run images:list
npm run images:list -- --place=posebyen
npm run images:list -- --status=pending

# Approve or reject one candidate
npm run images:approve -- --candidate=wikimedia:posebyen:6a3f37f807358c53
npm run images:reject -- --candidate=wikimedia:posebyen:358e7a59a89fc6b2

# Apply approved candidates to place records
npm run images:apply
npm run images:apply -- --place=posebyen
```

Notes:

- Discovery only creates `pending` candidates. Nothing is shown in the app until you approve and apply.
- `npm run seed` resets the `places` table back to the curated seed data. Candidate records remain available for review.
- Wikimedia discovery is intentionally semi-automatic. Some places return perfect building shots, others return adjacent or overly narrow photos, so manual approval still matters.
- The mobile app now includes a basic in-app review screen under `Settings -> Open Image Review`.
