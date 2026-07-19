import type { TFunction } from 'i18next';

import i18n from '@/src/i18n';
import type { OpeningHoursData, OpeningHoursRange, Place } from '@/src/data/places';

type MinutesRange = {
  start: number;
  end: number;
};

type HoursProfile =
  | {
      kind: 'always-open';
      summaryKey: string;
    }
  | {
      kind: 'scheduled';
      summaryKey: string;
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

const WEEKLY_DAY_ORDER: { dayIndex: number; labelKey: string }[] = [
  { dayIndex: 1, labelKey: 'placeHours.weekdayShort.mon' },
  { dayIndex: 2, labelKey: 'placeHours.weekdayShort.tue' },
  { dayIndex: 3, labelKey: 'placeHours.weekdayShort.wed' },
  { dayIndex: 4, labelKey: 'placeHours.weekdayShort.thu' },
  { dayIndex: 5, labelKey: 'placeHours.weekdayShort.fri' },
  { dayIndex: 6, labelKey: 'placeHours.weekdayShort.sat' },
  { dayIndex: 0, labelKey: 'placeHours.weekdayShort.sun' },
];

const DAY_NAME_KEYS = [
  'placeHours.day.sunday',
  'placeHours.day.monday',
  'placeHours.day.tuesday',
  'placeHours.day.wednesday',
  'placeHours.day.thursday',
  'placeHours.day.friday',
  'placeHours.day.saturday',
];

function defaultT(key: string, options?: Record<string, unknown>) {
  return i18n.t(key, options as any) as string;
}

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
  summaryKey: 'placeHours.profile.outdoor',
};

const LANDMARK_DAYTIME_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summaryKey: 'placeHours.profile.landmarkDaytime',
  rangesByDay: createSchedule([0, 1, 2, 3, 4, 5, 6], 9, 18),
};

const MUSEUM_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summaryKey: 'placeHours.profile.museum',
  rangesByDay: {
    ...createSchedule([2, 3, 4, 5, 6], 11, 17),
    ...createSchedule([0], 12, 16),
  },
};

const CULTURE_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summaryKey: 'placeHours.profile.culture',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4, 5], 10, 17),
    ...createSchedule([6], 11, 17),
    ...createSchedule([0], 12, 16),
  },
};

const CAFE_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summaryKey: 'placeHours.profile.cafe',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4, 5], 8, 18),
    ...createSchedule([6], 9, 18),
    ...createSchedule([0], 10, 17),
  },
};

const RESTAURANT_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summaryKey: 'placeHours.profile.restaurant',
  rangesByDay: {
    ...createSchedule([1, 2, 3, 4], 12, 22),
    ...createSchedule([5, 6], 12, 23),
    ...createSchedule([0], 13, 21),
  },
};

const SHOPPING_PROFILE: HoursProfile = {
  kind: 'scheduled',
  summaryKey: 'placeHours.profile.shopping',
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

function formatRangeList(t: TFunction, ranges: MinutesRange[]) {
  if (!ranges.length) return t('placeHours.closed') as string;
  return ranges.map((range) => `${formatMinutes(range.start)}-${formatMinutes(range.end)}`).join(', ');
}

function getDayLabel(t: TFunction, dayOffset: number, dayIndex: number) {
  if (dayOffset === 0) return t('placeHours.day.today') as string;
  if (dayOffset === 1) return t('placeHours.day.tomorrow') as string;

  const key = DAY_NAME_KEYS[dayIndex];
  return key ? (t(key) as string) : (t('placeHours.day.another') as string);
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
  t: TFunction,
  profile: HoursProfile,
  todayIndex: number
): WeeklyHoursRow[] {
  if (profile.kind === 'always-open') {
    return WEEKLY_DAY_ORDER.map((entry) => ({
      dayIndex: entry.dayIndex,
      label: t(entry.labelKey) as string,
      hoursText: t('placeHours.allDay') as string,
      isToday: entry.dayIndex === todayIndex,
    }));
  }

  return WEEKLY_DAY_ORDER.map((entry) => ({
    dayIndex: entry.dayIndex,
    label: t(entry.labelKey) as string,
    hoursText: formatRangeList(t, profile.rangesByDay[entry.dayIndex] ?? []),
    isToday: entry.dayIndex === todayIndex,
  }));
}

function createWeeklyRowsFromOpeningHours(
  t: TFunction,
  openingHours: OpeningHoursData,
  todayIndex: number
): WeeklyHoursRow[] {
  if (openingHours.mode === 'always-open') {
    return WEEKLY_DAY_ORDER.map((entry) => ({
      dayIndex: entry.dayIndex,
      label: t(entry.labelKey) as string,
      hoursText: t('placeHours.allDay') as string,
      isToday: entry.dayIndex === todayIndex,
    }));
  }

  return WEEKLY_DAY_ORDER.map((entry) => ({
    dayIndex: entry.dayIndex,
    label: t(entry.labelKey) as string,
    hoursText: formatRangeList(
      t,
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

function getVerifiedHoursStatus(t: TFunction, place: Place, openingHours: OpeningHoursData, date: Date): PlaceOpenStatus {
  if (openingHours.mode === 'always-open') {
    return {
      state: 'all-day',
      shortLabel: t('placeHours.status.openAllDay') as string,
      detail: t('placeHours.detail.verifiedAllDay') as string,
      note: place.visitInfo?.hoursLastCheckedAt
        ? (t('placeHours.note.verifiedChecked', { date: new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB') }) as string)
        : (t('placeHours.note.verifiedFromSource') as string),
      verified: true,
    };
  }

  const { dayIndex, minutes } = getNowParts(date);
  const todayRanges = openingHours.days[String(dayIndex) as keyof OpeningHoursData['days']] ?? [];
  const activeRange = todayRanges.map(toRangeMinutes).find((range) => minutes >= range.start && minutes < range.end);

  if (activeRange) {
    return {
      state: 'open',
      shortLabel: t('placeHours.status.openNow') as string,
      detail: t('placeHours.detail.verifiedOpenUntil', { time: formatMinutes(activeRange.end) }) as string,
      note: place.visitInfo?.hoursLastCheckedAt
        ? (t('placeHours.note.lastChecked', { date: new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB') }) as string)
        : (t('placeHours.note.verifiedFromSource') as string),
      verified: true,
    };
  }

  const nextOpening = getVerifiedNextOpening(openingHours, dayIndex, minutes);
  const nextOpeningText = nextOpening
    ? (t('placeHours.detail.opensAt', { day: getDayLabel(t, nextOpening.dayOffset, nextOpening.dayIndex), time: nextOpening.start }) as string)
    : (t('placeHours.detail.unclear') as string);

  return {
    state: 'closed',
    shortLabel: t('placeHours.status.closedNow') as string,
    detail: t('placeHours.detail.verifiedClosedWithNext', { nextOpeningText }) as string,
    note: place.visitInfo?.hoursLastCheckedAt
      ? (t('placeHours.note.lastChecked', { date: new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB') }) as string)
      : (t('placeHours.note.verifiedFromSource') as string),
    verified: true,
  };
}

export function getPlaceOpenStatus(place: Place, t: TFunction = defaultT as TFunction, date = new Date()): PlaceOpenStatus {
  if (place.visitInfo?.temporarilyClosed) {
    return {
      state: 'temporarily-closed',
      shortLabel: t('placeHours.status.temporarilyClosed') as string,
      detail: t('placeHours.detail.temporarilyClosed') as string,
      verified: Boolean(place.visitInfo?.hoursVerified),
    };
  }

  if (place.visitInfo?.hoursVerified && place.visitInfo.openingHours) {
    return getVerifiedHoursStatus(t, place, place.visitInfo.openingHours, date);
  }

  const profile = getHoursProfile(place);
  const summary = t(profile.summaryKey) as string;

  if (profile.kind === 'always-open') {
    return {
      state: 'all-day',
      shortLabel: t('placeHours.status.usuallyOpenAllDay') as string,
      detail: summary,
      note: t('placeHours.note.publicOutdoor') as string,
      verified: false,
    };
  }

  const { dayIndex, minutes } = getNowParts(date);
  const todayRanges = profile.rangesByDay[dayIndex] ?? [];
  const activeRange = todayRanges.find((range) => minutes >= range.start && minutes < range.end);

  if (activeRange) {
    return {
      state: 'open',
      shortLabel: t('placeHours.status.likelyOpenNow') as string,
      detail: t('placeHours.detail.likelyOpenUntil', { summary, time: formatMinutes(activeRange.end) }) as string,
      note: t('placeHours.note.estimatedNotVerified') as string,
      verified: false,
    };
  }

  const nextOpening = getNextOpening(profile, dayIndex, minutes);
  const nextOpeningText = nextOpening
    ? (t('placeHours.detail.likelyOpensAt', { day: getDayLabel(t, nextOpening.dayOffset, nextOpening.dayIndex), time: formatMinutes(nextOpening.start) }) as string)
    : (t('placeHours.detail.unclear') as string);

  return {
    state: 'closed',
    shortLabel: t('placeHours.status.likelyClosedNow') as string,
    detail: t('placeHours.detail.likelyClosedWithNext', { summary, nextOpeningText }) as string,
    note: t('placeHours.note.estimatedNotVerified') as string,
    verified: false,
  };
}

export function getWeeklyHoursSchedule(place: Place, t: TFunction = defaultT as TFunction, date = new Date()): WeeklyHoursSchedule {
  const { dayIndex } = getNowParts(date);

  if (place.visitInfo?.hoursVerified && place.visitInfo.openingHours) {
    return {
      verified: true,
      note: place.visitInfo.hoursLastCheckedAt
        ? (t('placeHours.weeklyNote.verifiedChecked', { date: new Date(place.visitInfo.hoursLastCheckedAt).toLocaleDateString('en-GB') }) as string)
        : (t('placeHours.weeklyNote.verifiedFromSource') as string),
      rows: createWeeklyRowsFromOpeningHours(t, place.visitInfo.openingHours, dayIndex),
    };
  }

  const profile = getHoursProfile(place);
  return {
    verified: false,
    note: t('placeHours.weeklyNote.estimatedNotVerified') as string,
    rows: createWeeklyRowsFromProfile(t, profile, dayIndex),
  };
}
