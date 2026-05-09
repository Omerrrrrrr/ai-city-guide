import type { OpeningHoursData, OpeningHoursRange, Place } from '@/src/data/places';

type MinutesRange = {
  start: number;
  end: number;
};

type HoursProfile =
  | {
      kind: 'always-open';
      summary: string;
    }
  | {
      kind: 'scheduled';
      summary: string;
      rangesByDay: Partial<Record<number, MinutesRange[]>>;
    };

export type PlaceOpenStatus = {
  state: 'open' | 'closed' | 'all-day' | 'temporarily-closed' | 'unknown';
  shortLabel: string;
  detail: string;
  note?: string;
  verified: boolean;
};

export type WeeklyHoursRow = {
  dayIndex: number;
  label: string;
  hoursText: string;
  isToday: boolean;
};

export type WeeklyHoursSchedule = {
  verified: boolean;
  note: string;
  rows: WeeklyHoursRow[];
};

const PLACE_TIMEZONE = 'Europe/Oslo';
const WEEKDAY_TO_INDEX: Record<string, number> = {
  Sun: 0,
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
};

const CLOCK_FORMATTER = new Intl.DateTimeFormat('en-GB', {
  timeZone: PLACE_TIMEZONE,
  weekday: 'short',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

const WEEKLY_DAY_ORDER: { dayIndex: number; label: string }[] = [
  { dayIndex: 1, label: 'Mon' },
  { dayIndex: 2, label: 'Tue' },
  { dayIndex: 3, label: 'Wed' },
  { dayIndex: 4, label: 'Thu' },
  { dayIndex: 5, label: 'Fri' },
  { dayIndex: 6, label: 'Sat' },
  { dayIndex: 0, label: 'Sun' },
];

function toMinutes(time: string) {
  const [hour, minute] = time.split(':').map(Number);
  return hour * 60 + minute;
}

function createDayRange(startHour: number, endHour: number): MinutesRange {
  return {
    start: startHour * 60,
    end: endHour * 60,
  };
}

function toRangeMinutes(range: OpeningHoursRange): MinutesRange {
  return {
    start: toMinutes(range.start),
    end: toMinutes(range.end),
  };
}

function createSchedule(days: number[], startHour: number, endHour: number) {
  return Object.fromEntries(days.map((day) => [day, [createDayRange(startHour, endHour)]]));
}

const OUTDOOR_PROFILE: HoursProfile = {
  kind: 'always-open',
  summary: 'Usually accessible all day.',
};

const LANDMARK_DAYTIME_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summary: 'Estimated daytime access for landmarks.',
  rangesByDay: createSchedule([0, 1, 2, 3, 4, 5, 6], 9, 18),
};

const MUSEUM_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summary: 'Estimated museum-style hours.',
  rangesByDay: {
    ...createSchedule([2, 3, 4, 5, 6], 11, 17),
    ...createSchedule([0], 12, 16),
  },
};

const CULTURE_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summary: 'Estimated venue hours for cultural stops.',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4, 5], 10, 17),
    ...createSchedule([6], 11, 17),
    ...createSchedule([0], 12, 16),
  },
};

const CAFE_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summary: 'Estimated cafe hours.',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4, 5], 8, 18),
    ...createSchedule([6], 9, 18),
    ...createSchedule([0], 10, 17),
  },
};

const RESTAURANT_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summary: 'Estimated restaurant hours.',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4], 12, 22),
    ...createSchedule([5, 6], 12, 23),
    ...createSchedule([0], 13, 21),
  },
};

const SHOPPING_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summary: 'Estimated shopping hours.',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4, 5], 10, 20),
    ...createSchedule([6], 10, 18),
  },
};

function getNowParts(date = new Date()) {
  const parts = CLOCK_FORMATTER.formatToParts(date);
  const weekday = parts.find((part) => part.type === 'weekday')?.value ?? 'Mon';
  const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? '12');
  const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? '0');

  return {
    dayIndex: WEEKDAY_TO_INDEX[weekday] ?? 1,
    minutes: hour * 60 + minute,
  };
}

function formatMinutes(minutes: number) {
  const hour = Math.floor(minutes / 60);
  const minute = minutes % 60;
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

function formatRangeList(ranges: MinutesRange[]) {
  if (!ranges.length) return 'Closed';
  return ranges.map((range) => `${formatMinutes(range.start)}-${formatMinutes(range.end)}`).join(', ');
}

function getDayLabel(dayOffset: number, dayIndex: number) {
  if (dayOffset === 0) return 'today';
  if (dayOffset === 1) return 'tomorrow';

  const dayLabels = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  return dayLabels[dayIndex] ?? 'another day';
}

function getHoursProfile(place: Place): HoursProfile {
  if (
    place.category === 'walking-area' ||
    place.category === 'beach' ||
    place.category === 'viewpoint' ||
    place.category === 'square-street'
  ) {
    return OUTDOOR_PROFILE;
  }

  if (place.category === 'museum') return MUSEUM_PROFILE;
  if (place.category === 'cultural-spot') return CULTURE_PROFILE;
  if (place.category === 'cafe') return CAFE_PROFILE;
  if (place.category === 'restaurant') return RESTAURANT_PROFILE;
  if (place.category === 'shopping-area') return SHOPPING_PROFILE;

  if (place.category === 'landmark') {
    if (place.tags.includes('outdoor')) {
      return OUTDOOR_PROFILE;
    }

    return LANDMARK_DAYTIME_PROFILE;
  }

  return LANDMARK_DAYTIME_PROFILE;
}

function createWeeklyRowsFromProfile(
  profile: HoursProfile,
  todayIndex: number
): WeeklyHoursRow[] {
  if (profile.kind === 'always-open') {
    return WEEKLY_DAY_ORDER.map((entry) => ({
      dayIndex: entry.dayIndex,
      label: entry.label,
      hoursText: 'All day',
      isToday: entry.dayIndex === todayIndex,
    }));
  }

  return WEEKLY_DAY_ORDER.map((entry) => ({
    dayIndex: entry.dayIndex,
    label: entry.label,
    hoursText: formatRangeList(profile.rangesByDay[entry.dayIndex] ?? []),
    isToday: entry.dayIndex === todayIndex,
  }));
}

function createWeeklyRowsFromOpeningHours(
  openingHours: OpeningHoursData,
  todayIndex: number
): WeeklyHoursRow[] {
  if (openingHours.mode === 'always-open') {
    return WEEKLY_DAY_ORDER.map((entry) => ({
      dayIndex: entry.dayIndex,
      label: entry.label,
      hoursText: 'All day',
      isToday: entry.dayIndex === todayIndex,
    }));
  }

  return WEEKLY_DAY_ORDER.map((entry) => ({
    dayIndex: entry.dayIndex,
    label: entry.label,
    hoursText: formatRangeList(
      (openingHours.days[String(entry.dayIndex) as keyof OpeningHoursData['days']] ?? []).map(
        toRangeMinutes
      )
    ),
    isToday: entry.dayIndex === todayIndex,
  }));
}

function getNextOpening(profile: Extract<HoursProfile, { kind: 'scheduled' }>, dayIndex: number, minutes: number) {
  for (let offset = 0; offset < 7; offset += 1) {
    const targetDay = (dayIndex + offset) % 7;
    const ranges = profile.rangesByDay[targetDay] ?? [];
    const nextRange = ranges.find((range) => offset > 0 || range.start > minutes);

    if (nextRange) {
      return {
        dayOffset: offset,
        dayIndex: targetDay,
        start: nextRange.start,
      };
    }
  }

  return null;
}

function getVerifiedNextOpening(openingHours: OpeningHoursData, dayIndex: number, minutes: number) {
  for (let offset = 0; offset < 7; offset += 1) {
    const targetDay = String((dayIndex + offset) % 7) as keyof OpeningHoursData['days'];
    const ranges = openingHours.days[targetDay] ?? [];
    const nextRange = ranges.find((range) => offset > 0 || toMinutes(range.start) > minutes);

    if (nextRange) {
      return {
        dayOffset: offset,
        dayIndex: Number(targetDay),
        start: nextRange.start,
      };
    }
  }

  return null;
}

function getVerifiedHoursStatus(place: Place, openingHours: OpeningHoursData, date: Date): PlaceOpenStatus {
  if (openingHours.mode === 'always-open') {
    return {
      state: 'all-day',
      shortLabel: 'Open all day',
      detail: 'Verified public access throughout the day.',
      note: place.visitInfo?.hoursLastCheckedAt
        ? `Verified hours checked on ${new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB')}.`
        : 'Verified from a linked source.',
      verified: true,
    };
  }

  const { dayIndex, minutes } = getNowParts(date);
  const todayRanges = openingHours.days[String(dayIndex) as keyof OpeningHoursData['days']] ?? [];
  const activeRange = todayRanges.map(toRangeMinutes).find((range) => minutes >= range.start && minutes < range.end);

  if (activeRange) {
    return {
      state: 'open',
      shortLabel: 'Open now',
      detail: `Verified hours. Open until ${formatMinutes(activeRange.end)} today.`,
      note: place.visitInfo?.hoursLastCheckedAt
        ? `Last checked on ${new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB')}.`
        : 'Verified from a linked source.',
      verified: true,
    };
  }

  const nextOpening = getVerifiedNextOpening(openingHours, dayIndex, minutes);
  const nextOpeningText = nextOpening
    ? `Opens ${getDayLabel(nextOpening.dayOffset, nextOpening.dayIndex)} around ${nextOpening.start}.`
    : 'Opening time is unclear right now.';

  return {
    state: 'closed',
    shortLabel: 'Closed now',
    detail: `Verified hours. ${nextOpeningText}`,
    note: place.visitInfo?.hoursLastCheckedAt
      ? `Last checked on ${new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB')}.`
      : 'Verified from a linked source.',
    verified: true,
  };
}

export function getPlaceOpenStatus(place: Place, date = new Date()): PlaceOpenStatus {
  if (place.visitInfo?.temporarilyClosed) {
    return {
      state: 'temporarily-closed',
      shortLabel: 'Temporarily closed',
      detail: 'This place is marked as temporarily closed right now.',
      verified: Boolean(place.visitInfo?.hoursVerified),
    };
  }

  if (place.visitInfo?.hoursVerified && place.visitInfo.openingHours) {
    return getVerifiedHoursStatus(place, place.visitInfo.openingHours, date);
  }

  const profile = getHoursProfile(place);

  if (profile.kind === 'always-open') {
    return {
      state: 'all-day',
      shortLabel: 'Usually open all day',
      detail: profile.summary,
      note: 'Public outdoor places are generally accessible, but weather and light still matter.',
      verified: false,
    };
  }

  const { dayIndex, minutes } = getNowParts(date);
  const todayRanges = profile.rangesByDay[dayIndex] ?? [];
  const activeRange = todayRanges.find((range) => minutes >= range.start && minutes < range.end);

  if (activeRange) {
    return {
      state: 'open',
      shortLabel: 'Likely open now',
      detail: `${profile.summary} Open until about ${formatMinutes(activeRange.end)} today.`,
      note: 'Estimated from venue type, not live verified hours.',
      verified: false,
    };
  }

  const nextOpening = getNextOpening(profile, dayIndex, minutes);
  const nextOpeningText = nextOpening
    ? `Likely opens ${getDayLabel(nextOpening.dayOffset, nextOpening.dayIndex)} around ${formatMinutes(nextOpening.start)}.`
    : 'Opening time is unclear right now.';

  return {
    state: 'closed',
    shortLabel: 'Likely closed now',
    detail: `${profile.summary} ${nextOpeningText}`,
    note: 'Estimated from venue type, not live verified hours.',
    verified: false,
  };
}

export function getWeeklyHoursSchedule(place: Place, date = new Date()): WeeklyHoursSchedule {
  const { dayIndex } = getNowParts(date);

  if (place.visitInfo?.hoursVerified && place.visitInfo.openingHours) {
    return {
      verified: true,
      note: place.visitInfo.hoursLastCheckedAt
        ? `Verified weekly hours. Last checked on ${new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB')}.`
        : 'Verified weekly hours from a linked source.',
      rows: createWeeklyRowsFromOpeningHours(place.visitInfo.openingHours, dayIndex),
    };
  }

  const profile = getHoursProfile(place);
  return {
    verified: false,
    note: 'Estimated weekly hours from venue type, not live verified data.',
    rows: createWeeklyRowsFromProfile(profile, dayIndex),
  };
}
