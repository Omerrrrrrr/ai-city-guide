import 'dotenv/config';

import { closeDb, connectDb } from './db';
import { ensureSchema } from './ensure-schema';
import { approveImageCandidate } from './image-candidate-service';
import { parseCliArgs, readStringArg } from './cli-args';

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const candidateId = readStringArg(args, 'candidate');

  if (!candidateId) {
    throw new Error('Missing --candidate=<candidateId>');
  }

  await connectDb();

  try {
    await ensureSchema();
    const candidate = await approveImageCandidate(candidateId);

    // eslint-disable-next-line no-console
    console.log(`[approve] ${candidate.id} approved for ${candidate.placeId}`);
  } finally {
    await closeDb();
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(error);
  process.exit(1);
});
