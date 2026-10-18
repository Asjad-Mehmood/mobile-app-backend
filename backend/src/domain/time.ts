const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(tz, f);
  }
  return f;
}

export interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  dateIso: string;
  minuteOfDay: number;
}

/** Wall-clock date/time of [epochMs] in [tz]. */
export function zonedParts(epochMs: number, tz: string): ZonedParts {
  const parts = Object.fromEntries(formatter(tz).formatToParts(new Date(epochMs)).map((p) => [p.type, p.value]));
  const year = Number(parts.year);
  const month = Number(parts.month);
  const day = Number(parts.day);
  const hour = Number(parts.hour);
  const minute = Number(parts.minute);
  const second = Number(parts.second);
  return {
    year,
    month,
    day,
    hour,
    minute,
    second,
    dateIso: `${parts.year}-${parts.month}-${parts.day}`,
    minuteOfDay: hour * 60 + minute,
  };
}

function offsetMs(epochMs: number, tz: string): number {
  const p = zonedParts(epochMs, tz);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - (epochMs - (((epochMs % 1000) + 1000) % 1000));
}

/** Epoch millis of [minuteOfDay] on [dateIso] (YYYY-MM-DD) in [tz]. */
export function zonedToEpoch(dateIso: string, minuteOfDay: number, tz: string): number {
  const [y, m, d] = dateIso.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d, 0, minuteOfDay);
  const first = offsetMs(guess, tz);
  let t = guess - first;
  const second = offsetMs(t, tz);
  if (second !== first) t = guess - second;
  return t;
}

export function addDays(dateIso: string, days: number): string {
  const [y, m, d] = dateIso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

export function todayIn(tz: string, nowMs: number): string {
  return zonedParts(nowMs, tz).dateIso;
}

function hhmm(minuteOfDay: number): string {
  const h24 = Math.floor(minuteOfDay / 60);
  const m = minuteOfDay % 60;
  const suffix = h24 >= 12 && h24 < 24 ? 'PM' : 'AM';
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${String(h12).padStart(2, '0')}:${String(m).padStart(2, '0')} ${suffix}`;
}

/** "08:00 AM - 10:00 AM" */
export function windowLabel(start: number, end: number): string {
  return `${hhmm(start)} - ${hhmm(end)}`;
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "Today", "Tomorrow" or "Tue 20 Oct". */
export function dayLabel(dateIso: string, todayIso: string): string {
  if (dateIso === todayIso) return 'Today';
  if (dateIso === addDays(todayIso, 1)) return 'Tomorrow';
  const [y, m, d] = dateIso.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return `${DAYS[date.getUTCDay()]} ${d} ${MONTHS[m - 1]}`;
}
