import { z } from 'zod';

export const HOURS_DAY_KEYS = ['0', '1', '2', '3', '4', '5', '6'] as const;

export type HoursDayKey = (typeof HOURS_DAY_KEYS)[number];

export type OpeningHoursRange = {
  start: string;
  end: string;
};

export type OpeningHoursData = {
  timezone: string;
  mode: 'always-open' | 'scheduled';
  days: Record<HoursDayKey, OpeningHoursRange[]>;
};

const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

function createEmptyDays(): Record<HoursDayKey, OpeningHoursRange[]> {
  return {
    '0': [],
    '1': [],
    '2': [],
    '3': [],
    '4': [],
    '5': [],
    '6': [],
  };
}

function toMinutes(time: string) {
  const [hour, minute] = time.split(':').map(Number);
  return hour * 60 + minute;
}

const rangeSchema = z
  .object({
    start: z.string().regex(TIME_PATTERN, 'Invalid start time'),
    end: z.string().regex(TIME_PATTERN, 'Invalid end time'),
  })
  .superRefine((value, ctx) => {
    if (toMinutes(value.end) <= toMinutes(value.start)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'End time must be later than start time',
      });
    }
  });

const dayRangesSchema = z.array(rangeSchema).superRefine((ranges, ctx) => {
  const sorted = [...ranges].sort((left, right) => left.start.localeCompare(right.start));

  for (let index = 0; index < sorted.length - 1; index += 1) {
    const current = sorted[index];
    const next = sorted[index + 1];

    if (toMinutes(current.end) > toMinutes(next.start)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Opening hour ranges cannot overlap',
      });
      return;
    }
  }
});

export const openingHoursSchema = z
  .object({
    timezone: z.string().trim().min(1).default('Europe/Oslo'),
    mode: z.enum(['always-open', 'scheduled']).default('scheduled'),
    days: z
      .object({
        '0': dayRangesSchema.default([]),
        '1': dayRangesSchema.default([]),
        '2': dayRangesSchema.default([]),
        '3': dayRangesSchema.default([]),
        '4': dayRangesSchema.default([]),
        '5': dayRangesSchema.default([]),
        '6': dayRangesSchema.default([]),
      })
      .default(createEmptyDays()),
  })
  .transform((value) => ({
    timezone: value.timezone,
    mode: value.mode,
    days: HOURS_DAY_KEYS.reduce<Record<HoursDayKey, OpeningHoursRange[]>>((accumulator, key) => {
      accumulator[key] = [...value.days[key]].sort((left, right) => left.start.localeCompare(right.start));
      return accumulator;
    }, createEmptyDays()),
  }));

export function parseOpeningHoursJson(value: string | null | undefined): OpeningHoursData | undefined {
  if (!value) return undefined;

  try {
    const parsed = JSON.parse(value);
    return openingHoursSchema.parse(parsed);
  } catch {
    return undefined;
  }
}
