import 'dotenv/config';
import { inArray } from 'drizzle-orm';

import { hasFlag, parseCliArgs, readNumberArg } from './cli-args';
import { closeDb, connectDb, db } from './db';
import { ensureSchema } from './ensure-schema';
import { liveGridCellStatus } from './schema';
import {
  cellsCoveringBbox,
  LIVE_GRID_CELL_TTL_DAYS,
  populateLiveCacheForCell,
  runWithConcurrency,
} from './place-discovery-service';
import { WORLD_POPULATION_CENTERS } from './world-population-centers';

// Manual, standalone version of what /places/nearby-live does reactively on
// a real user's first drag into an area — walks the world's most populous
// settlements ahead of time so a real user almost never pays that live
// multi-second Overture query cost themselves. No in-process scheduler is
// wired up yet (see live-explore plan notes): the app isn't deployed to a
// real host yet, so there's nowhere for an automatic nightly job to run.
// Once it is, wire this up via the hosting platform's own scheduled-job
// feature (Render Cron Job / Railway Cron / etc.) calling
// `npm run prewarm:live-pins`; until then, run it by hand.
const PREWARM_SEED_RADIUS_KM = 3;
const PREWARM_CONCURRENCY = 2;
const PREWARM_CELL_DELAY_MS = 500;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const limit = Math.max(1, readNumberArg(args, 'limit') ?? WORLD_POPULATION_CENTERS.length);
  const dryRun = hasFlag(args, 'dry-run');
  const seeds = WORLD_POPULATION_CENTERS.slice(0, limit);

  await connectDb();
  try {
    await ensureSchema();

    const ttlCutoff = Date.now() - LIVE_GRID_CELL_TTL_DAYS * 24 * 60 * 60 * 1000;
    const allCells = new Set<string>();
    for (const seed of seeds) {
      const latDelta = PREWARM_SEED_RADIUS_KM / 111;
      const lngDelta = PREWARM_SEED_RADIUS_KM / (111 * Math.cos((seed.lat * Math.PI) / 180));
      for (const cell of cellsCoveringBbox(seed.lat - latDelta, seed.lat + latDelta, seed.lng - lngDelta, seed.lng + lngDelta)) {
        allCells.add(cell);
      }
    }

    const cellList = Array.from(allCells);
    // eslint-disable-next-line no-console
    console.log(`[prewarm] ${seeds.length} seed cities → ${cellList.length} candidate grid cells`);

    const statuses = await db.select().from(liveGridCellStatus).where(inArray(liveGridCellStatus.gridCell, cellList));
    const freshCells = new Set(
      statuses.filter((s) => new Date(s.queriedAt).getTime() >= ttlCutoff).map((s) => s.gridCell)
    );
    const staleCells = cellList.filter((cell) => !freshCells.has(cell));

    // eslint-disable-next-line no-console
    console.log(`[prewarm] ${freshCells.size} already fresh, ${staleCells.length} to query`);

    if (dryRun) {
      // eslint-disable-next-line no-console
      console.log('[prewarm] --dry-run, stopping before any Overture queries');
      return;
    }

    let done = 0;
    let totalCandidates = 0;
    await runWithConcurrency(staleCells, PREWARM_CONCURRENCY, async (cell) => {
      const count = await populateLiveCacheForCell(cell);
      totalCandidates += count;
      done += 1;
      if (done % 25 === 0 || done === staleCells.length) {
        // eslint-disable-next-line no-console
        console.log(`[prewarm] ${done}/${staleCells.length} cells done`);
      }
      await sleep(PREWARM_CELL_DELAY_MS);
    });

    // eslint-disable-next-line no-console
    console.log(`[prewarm] done — ${staleCells.length} cells queried, ${totalCandidates} candidates cached`);
  } finally {
    await closeDb();
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(error);
  process.exit(1);
});
