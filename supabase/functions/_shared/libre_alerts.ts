/**
 * Pure Libre alert evaluation for cron (mirrors Dart LibreAlertLogic).
 */

export type AlertZone = 'ok' | 'hypo' | 'hyper'

export type AlertDecision = {
  zone: AlertZone
  shouldNotify: boolean
  type?: 'libre_hypo' | 'libre_hyper' | 'libre_stale'
  title?: string
  body?: string
}

export type AlertThresholds = {
  hypoMgdl: number
  hyperMgdl: number
  staleMinutes: number
  realertMinutes?: number
}

const DEFAULT_REALERT = 20

export function zoneForGlucose(
  mgdl: number,
  previous: AlertZone,
  t: AlertThresholds,
): AlertZone {
  const hypoClear = t.hypoMgdl + 10
  const hyperClear = t.hyperMgdl - 20
  switch (previous) {
    case 'hypo':
      if (mgdl >= hypoClear) {
        return mgdl > t.hyperMgdl ? 'hyper' : 'ok'
      }
      return 'hypo'
    case 'hyper':
      if (mgdl <= hyperClear) {
        return mgdl < t.hypoMgdl ? 'hypo' : 'ok'
      }
      return 'hyper'
    default:
      if (mgdl < t.hypoMgdl) return 'hypo'
      if (mgdl > t.hyperMgdl) return 'hyper'
      return 'ok'
  }
}

export function evaluateReading(opts: {
  glucoseMgdl: number
  recordedAt: Date | null
  trendLabel?: string
  previousZone: AlertZone
  now: Date
  lastAlertAt: Date | null
  lastAlertedRecordedAt?: Date | null
  thresholds: AlertThresholds
}): AlertDecision {
  const t = opts.thresholds
  const realert = t.realertMinutes ?? DEFAULT_REALERT
  const at = opts.recordedAt
  if (
    at &&
    opts.now.getTime() - at.getTime() > t.staleMinutes * 60_000
  ) {
    return { zone: opts.previousZone, shouldNotify: false }
  }

  const next = zoneForGlucose(opts.glucoseMgdl, opts.previousZone, t)
  if (next === 'ok') {
    return { zone: 'ok', shouldNotify: false }
  }

  const sameSample =
    !!opts.lastAlertedRecordedAt &&
    !!at &&
    opts.lastAlertedRecordedAt.getTime() === at.getTime()
  if (sameSample) {
    return { zone: next, shouldNotify: false }
  }

  const entered = next !== opts.previousZone
  const due =
    !opts.lastAlertAt ||
    opts.now.getTime() - opts.lastAlertAt.getTime() >= realert * 60_000
  if (!entered && !due) {
    return { zone: next, shouldNotify: false }
  }

  const trend = opts.trendLabel?.trim() ? ` ${opts.trendLabel}` : ''
  if (next === 'hypo') {
    return {
      zone: next,
      shouldNotify: true,
      type: 'libre_hypo',
      title: 'Glicose baixa',
      body: `${opts.glucoseMgdl} mg/dL${trend}`,
    }
  }
  return {
    zone: next,
    shouldNotify: true,
    type: 'libre_hyper',
    title: 'Glicose alta',
    body: `${opts.glucoseMgdl} mg/dL${trend}`,
  }
}

export function evaluateStale(opts: {
  now: Date
  lastSuccessSyncAt: Date | null
  sampleRecordedAt?: Date | null
  libreConnected: boolean
  alertsEnabled: boolean
  lastStaleAlertAt: Date | null
  consecutiveFailures?: number
  thresholds: AlertThresholds
}): AlertDecision {
  if (!opts.alertsEnabled || !opts.libreConnected) {
    return { zone: 'ok', shouldNotify: false }
  }
  const t = opts.thresholds
  const realert = t.realertMinutes ?? DEFAULT_REALERT
  const syncStale =
    !opts.lastSuccessSyncAt ||
    opts.now.getTime() - opts.lastSuccessSyncAt.getTime() >
      t.staleMinutes * 60_000
  const sampleStale =
    !!opts.sampleRecordedAt &&
    opts.now.getTime() - opts.sampleRecordedAt.getTime() >
      t.staleMinutes * 60_000
  const stale =
    syncStale || sampleStale || (opts.consecutiveFailures ?? 0) >= 3
  if (!stale) return { zone: 'ok', shouldNotify: false }

  const due =
    !opts.lastStaleAlertAt ||
    opts.now.getTime() - opts.lastStaleAlertAt.getTime() >= realert * 60_000
  if (!due) return { zone: 'ok', shouldNotify: false }

  return {
    zone: 'ok',
    shouldNotify: true,
    type: 'libre_stale',
    title: 'Sensor sem dados',
    body: 'Não recebemos glicose recente do Libre. Verifique a conexão.',
  }
}

export function trendLabel(trend: number | null | undefined): string {
  switch (trend) {
    case 1:
      return '↓↓'
    case 2:
      return '↓'
    case 3:
      return '→'
    case 4:
      return '↑'
    case 5:
      return '↑↑'
    default:
      return ''
  }
}
