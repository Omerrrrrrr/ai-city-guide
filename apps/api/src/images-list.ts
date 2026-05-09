import 'dotenv/config';

import { closeDb, connectDb } from './db';
import { ensureSchema } from './ensure-schema';
import { listImageCandidates } from './image-candidate-service';
import { parseCliArgs, readStringArg } from './cli-args';

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const placeQuery = readStringArg(args, 'place');
  const statusQuery = readStringArg(args, 'status');

  await connectDb();

  try {
    await ensureSchema();

    const filtered = await listImageCandidates({
      placeQuery,
      status: (statusQuery as 'pending' | 'approved' | 'rejected' | 'applied' | undefined) ?? undefined,
    });

    if (!filtered.length) {
      // eslint-disable-next-line no-console
      console.log('No image candidates found.');
      return;
    }

    let currentPlaceId = '';
    for (const candidate of filtered) {
      if (candidate.placeId !== currentPlaceId) {
        currentPlaceId = candidate.placeId;
        // eslint-disable-next-line no-console
        console.log(`\n${candidate.placeId} · ${candidate.placeName}`);
      }

      // eslint-disable-next-line no-console
      console.log(
        `  [${candidate.status}] rank=${candidate.rank} confidence=${candidate.confidence} id=${candidate.id}`
      );
      // eslint-disable-next-line no-console
      console.log(`    ${candidate.pageTitle}`);
      // eslint-disable-next-line no-console
      console.log(`    ${candidate.sourceUrl}`);
    }
  } finally {
    await closeDb();
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(error);
  process.exit(1);
});
