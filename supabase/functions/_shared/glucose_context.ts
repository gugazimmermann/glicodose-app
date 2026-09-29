/**
 * Weekday-hour glucose drop patterns.
 * Mirrors lib/services/glucose_context_logic.dart.
 */

export const LOOKBACK_DAYS = 28
export const MIN_DROP_MGDL = 25
export const MIN_OCCURRENCES = 3
export const MIN_DROP_RATE = 0.6
export const SNACK_CARBS_G = 15
export const LEAD_MINUTES = 20
export const MEAL_QUIET_MINUTES = 90
export const UPPER_MGDL = 180
export const RECOMPUTE_HOURS = 6
export const STRONG_RISE_TREND = 5
export const ALERT_TITLE = 'Padrão de glicemia'

const WEEKDAY_FULL = [
  '',
  'nas segundas-feiras',
  'nas terças-feiras',
  'nas quartas-feiras',
  'nas quintas-feiras',
  'nas sextas-feiras',
  'nos sábados',
  'nos domingos',
]

const WEEKDAY_SHORT: Record<string, number> = {
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
  Sun: 7,
}

export type GlucosePoint = {
  glucoseMgdl: number
  recordedAt: Date
}

export type ContextPattern = {
  weekday: number
  hour: number
  medianMgdl: number
  medianDropMgdl: number
  occurrences: number
  dropRate: number
  suggestCarbsG: number | null
}

export type LocalClock = {
  weekday: number
  hour: number
  minute: number
  year: number
  month: number
  day: number
}

export type ContextAlert = {
  pattern: ContextPattern
  slotDate: string
  title: string
  body: string
}

export function meetsPatternThreshold(
  dropDates: number,
  evaluatedDates: number,
): boolean {
  if (evaluatedDates <= 0 || dropDates < MIN_OCCURRENCES) return false
  return dropDates / evaluatedDates >= MIN_DROP_RATE
}

export function isInLeadWindow(
  nowWeekday: number,
  nowHour: number,
  nowMinute: number,
  patternWeekday: number,
  patternHour: number,
): boolean {
  const leadHour = patternHour === 0 ? 23 : patternHour - 1
  const leadWeekday = patternHour === 0
    ? (patternWeekday === 1 ? 7 : patternWeekday - 1)
    : patternWeekday
  const startMinute = 60 - LEAD_MINUTES
  return nowWeekday === leadWeekday &&
    nowHour === leadHour &&
    nowMinute >= startMinute
}

export function slotDate(
  year: number,
  month: number,
  day: number,
  nowHour: number,
  patternHour: number,
): string {
  if (patternHour === 0 && nowHour === 23) {
    const next = new Date(Date.UTC(year, month - 1, day))
    next.setUTCDate(next.getUTCDate() + 1)
    return formatDate(
      next.getUTCFullYear(),
      next.getUTCMonth() + 1,
      next.getUTCDate(),
    )
  }
  return formatDate(year, month, day)
}

export function alertBody(pattern: ContextPattern): string {
  const phrase = pattern.weekday >= 1 && pattern.weekday <= 7
    ? WEEKDAY_FULL[pattern.weekday]
    : 'nesse horário'
  const base =
    `Historicamente, ${phrase} às ${pattern.hour}h, sua glicemia cai.`
  if (pattern.suggestCarbsG == null) return base
  return `${base} Que tal um lanche de ${pattern.suggestCarbsG}g de carboidratos agora?`
}

export function zonedParts(instant: Date, timeZone: string): LocalClock {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: safeTimeZone(timeZone),
    weekday: 'short',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  })
  const bag: Record<string, string> = {}
  for (const part of fmt.formatToParts(instant)) {
    if (part.type !== 'literal') bag[part.type] = part.value
  }
  let hour = Number(bag.hour)
  if (hour === 24) hour = 0
  const weekday = WEEKDAY_SHORT[bag.weekday]
  if (!weekday || Number.isNaN(hour)) {
    throw new Error(`Fuso inválido: ${timeZone}`)
  }
  return {
    weekday,
    hour,
    minute: Number(bag.minute),
    year: Number(bag.year),
    month: Number(bag.month),
    day: Number(bag.day),
  }
}

export function safeTimeZone(name: string | null | undefined): string {
  const tz = name?.trim() || 'America/Sao_Paulo'
  try {
    Intl.DateTimeFormat('en-US', { timeZone: tz }).format(new Date())
    return tz
  } catch {
    return 'America/Sao_Paulo'
  }
}

export function detectPatterns(opts: {
  samples: GlucosePoint[]
  timezone: string
  now: Date
  hypoMgdl: number
}): ContextPattern[] {
  const timeZone = safeTimeZone(opts.timezone)
  const cutoff = opts.now.getTime() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000
  const buckets = new Map<string, number[]>()

  for (const sample of opts.samples) {
    const at = sample.recordedAt.getTime()
    if (at < cutoff) continue
    const local = zonedParts(sample.recordedAt, timeZone)
    const key = bucketKey(local.year, local.month, local.day, local.hour)
    const list = buckets.get(key)
    if (list) list.push(sample.glucoseMgdl)
    else buckets.set(key, [sample.glucoseMgdl])
  }

  const hourMedian = new Map<string, number>()
  for (const [key, values] of buckets) {
    hourMedian.set(key, median(values))
  }

  const evaluated = new Map<string, number>()
  const drops = new Map<string, Array<{ hourMgdl: number; dropMgdl: number }>>()

  for (const [key, value] of hourMedian) {
    const parts = parseBucket(key)
    const prevMedian = hourMedian.get(previousBucketKey(parts))
    if (prevMedian == null) continue
    const slot = `${parts.weekday}|${parts.hour}`
    evaluated.set(slot, (evaluated.get(slot) ?? 0) + 1)
    const drop = prevMedian - value
    if (drop < MIN_DROP_MGDL) continue
    const list = drops.get(slot)
    const row = { hourMgdl: value, dropMgdl: drop }
    if (list) list.push(row)
    else drops.set(slot, [row])
  }

  const patterns: ContextPattern[] = []
  for (const [slot, evaluatedDates] of evaluated) {
    const slotDrops = drops.get(slot) ?? []
    if (!meetsPatternThreshold(slotDrops.length, evaluatedDates)) continue
    const [weekdayRaw, hourRaw] = slot.split('|')
    const medianMgdl = median(slotDrops.map((d) => d.hourMgdl))
    patterns.push({
      weekday: Number(weekdayRaw),
      hour: Number(hourRaw),
      medianMgdl,
      medianDropMgdl: median(slotDrops.map((d) => d.dropMgdl)),
      occurrences: slotDrops.length,
      dropRate: slotDrops.length / evaluatedDates,
      suggestCarbsG: medianMgdl < opts.hypoMgdl ? SNACK_CARBS_G : null,
    })
  }

  patterns.sort((a, b) => a.weekday - b.weekday || a.hour - b.hour)
  return patterns
}

export function evaluateAlert(opts: {
  patterns: ContextPattern[]
  now: LocalClock
  currentMgdl: number
  hypoMgdl: number
  trend?: number | null
  recentMeal: boolean
  lastNotifiedOn: Record<string, string>
}): ContextAlert | null {
  if (opts.currentMgdl <= opts.hypoMgdl || opts.currentMgdl >= UPPER_MGDL) {
    return null
  }
  if (opts.trend === STRONG_RISE_TREND) return null
  if (opts.recentMeal) return null

  const ordered = [...opts.patterns].sort(
    (a, b) => a.weekday - b.weekday || a.hour - b.hour,
  )
  for (const pattern of ordered) {
    if (
      !isInLeadWindow(
        opts.now.weekday,
        opts.now.hour,
        opts.now.minute,
        pattern.weekday,
        pattern.hour,
      )
    ) {
      continue
    }
    const slot = slotDate(
      opts.now.year,
      opts.now.month,
      opts.now.day,
      opts.now.hour,
      pattern.hour,
    )
    const key = `${pattern.weekday}|${pattern.hour}`
    if (opts.lastNotifiedOn[key] === slot) continue
    return {
      pattern,
      slotDate: slot,
      title: ALERT_TITLE,
      body: alertBody(pattern),
    }
  }
  return null
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b)
  const n = sorted.length
  if (n === 0) throw new Error('median of empty list')
  if (n % 2 === 1) return sorted[Math.floor(n / 2)]
  return Math.round((sorted[n / 2 - 1] + sorted[n / 2]) / 2)
}

function bucketKey(year: number, month: number, day: number, hour: number) {
  return `${year}-${month}-${day}|${hour}`
}

function formatDate(year: number, month: number, day: number): string {
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
}

function parseBucket(key: string): {
  year: number
  month: number
  day: number
  hour: number
  weekday: number
} {
  const [date, hourRaw] = key.split('|')
  const [yearRaw, monthRaw, dayRaw] = date.split('-')
  const year = Number(yearRaw)
  const month = Number(monthRaw)
  const day = Number(dayRaw)
  const utc = new Date(Date.UTC(year, month - 1, day))
  const jsDay = utc.getUTCDay()
  return {
    year,
    month,
    day,
    hour: Number(hourRaw),
    weekday: jsDay === 0 ? 7 : jsDay,
  }
}

function previousBucketKey(current: {
  year: number
  month: number
  day: number
  hour: number
}): string {
  if (current.hour > 0) {
    return bucketKey(current.year, current.month, current.day, current.hour - 1)
  }
  const prev = new Date(Date.UTC(current.year, current.month - 1, current.day))
  prev.setUTCDate(prev.getUTCDate() - 1)
  return bucketKey(
    prev.getUTCFullYear(),
    prev.getUTCMonth() + 1,
    prev.getUTCDate(),
    23,
  )
}
