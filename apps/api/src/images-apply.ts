import 'dotenv/config';

import { parseCliArgs, readStringArg } from './cli-args';
import { closeDb, connectDb } from './db';
import { ensureSchema } from './ensure-schema';
import { applyApprovedImageCandidates } from './image-candidate-service';

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const candidateId = readStringArg(args, 'candidate');
  const placeQuery = readStringArg(args, 'place');

  await connectDb();

  try {
    await ensureSchema();
    const approvedCandidates = await applyApprovedImageCandidates({
      candidateId,
      placeId: placeQuery,
    });

    if (!approvedCandidates.length) {
      // eslint-disable-next-line no-console
      console.log('No approved image candidates to apply.');
      return;
    }

    for (const candidate of approvedCandidates) {
      // eslint-disable-next-line no-console
      console.log(`[apply] ${candidate.placeId} <= ${candidate.id}`);
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
