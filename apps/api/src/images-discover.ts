import 'dotenv/config';

import { hasFlag, parseCliArgs, readNumberArg, readStringArg } from './cli-args';
import { closeDb, connectDb, db } from './db';
import { ensureSchema } from './ensure-schema';
import { discoverImageCandidates } from './image-candidate-service';

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const placeQuery = readStringArg(args, 'place');
  const limit = Math.max(1, Math.min(10, readNumberArg(args, 'limit') ?? 5));
  const includeVerified = hasFlag(args, 'include-verified');

  await connectDb();

  try {
    await ensureSchema();

    const results = await discoverImageCandidates({ placeQuery, limit, includeVerified });

    let totalCandidates = 0;

    for (const result of results) {
      totalCandidates += result.discoveredCount;
      // eslint-disable-next-line no-console
      console.log(
        result.topCandidate
          ? `[discover] ${result.placeId}: ${result.discoveredCount} candidates, top=${result.topCandidate.pageTitle} (${result.topCandidate.confidence})`
          : `[discover] ${result.placeId}: no candidates found`
      );
    }

    // eslint-disable-next-line no-console
    console.log(`[discover] done, ${totalCandidates} candidates saved`);
  } finally {
    await closeDb();
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(error);
  process.exit(1);
});
