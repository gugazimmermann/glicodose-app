// Background sync for all connected LibreLinkUp users (cron every ~5 min).
// Deploy:
//   supabase secrets set LIBRELINKUP_CRON_SECRET='um-segredo-longo'
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{...}'
//   supabase functions deploy librelinkup-cron
//
// verify_jwt = false. Authenticate via Authorization: Bearer <LIBRELINKUP_CRON_SECRET>.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { syncUserGlucose } from '../_shared/libre_sync.ts'
import {
  evaluateReading,
  evaluateStale,
  trendLabel,
  type AlertThresholds,
  type AlertZone,
} from '../_shared/libre_alerts.ts'
import { sendFcmToTokens } from '../_shared/fcm.ts'
import {
  detectPatterns,
  evaluateAlert,
  LOOKBACK_DAYS,
  MEAL_QUIET_MINUTES,
  RECOMPUTE_HOURS,
  safeTimeZone,
  zonedParts,
  type ContextPattern,
} from '../_shared/glucose_context.ts'
import { isSupporterStatus } from '../_shared/supporter.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

type ProfileAlertRow = {
  libre_alerts_enabled: boolean
  libre_alert_hypo_mgdl: number
  libre_alert_hyper_mgdl: number
  libre_alert_stale_minutes: number
}

type AlertStateRow = {
  zone: AlertZone
  last_pushed_at: string | null
  last_stale_pushed_at: string | null
  last_alerted_recorded_at: string | null
}

async function pushAlertsForUser(
  // deno-lint-ignore no-explicit-any
  admin: any,
  userId: string,
  syncOk: boolean,
  glucose: {
    value: number
    trend: number | null
    recordedAt: string
  } | null,
): Promise<{ pushed: boolean; type?: string }> {
  const { data: profile } = await admin
    .from('profiles')
    .select(
      'libre_alerts_enabled, libre_alert_hypo_mgdl, libre_alert_hyper_mgdl, libre_alert_stale_minutes',
    )
    .eq('id', userId)
    .maybeSingle()

  const p = profile as ProfileAlertRow | null
  if (!p?.libre_alerts_enabled) {
    return { pushed: false }
  }

  const thresholds: AlertThresholds = {
    hypoMgdl: p.libre_alert_hypo_mgdl ?? 70,
    hyperMgdl: p.libre_alert_hyper_mgdl ?? 180,
    staleMinutes: p.libre_alert_stale_minutes ?? 20,
  }

  const { data: stateRow } = await admin
    .from('libre_alert_state')
    .select('zone, last_pushed_at, last_stale_pushed_at, last_alerted_recorded_at')
    .eq('user_id', userId)
    .maybeSingle()

  const state = (stateRow as AlertStateRow | null) ?? {
    zone: 'ok' as AlertZone,
    last_pushed_at: null,
    last_stale_pushed_at: null,
    last_alerted_recorded_at: null,
  }

  const { data: cred } = await admin
    .from('librelinkup_credentials')
    .select('last_sync_at')
    .eq('user_id', userId)
    .maybeSingle()

  const now = new Date()
  const lastSyncAt = cred?.last_sync_at
    ? new Date(cred.last_sync_at as string)
    : null

  // Rely on last_sync_at / sample age — do not force stale on first sync failure.
  let decision = evaluateStale({
    now,
    lastSuccessSyncAt: lastSyncAt,
    sampleRecordedAt: glucose?.recordedAt
      ? new Date(glucose.recordedAt)
      : null,
    libreConnected: true,
    alertsEnabled: true,
    lastStaleAlertAt: state.last_stale_pushed_at
      ? new Date(state.last_stale_pushed_at)
      : null,
    consecutiveFailures: 0,
    thresholds,
  })

  let nextZone: AlertZone = state.zone

  if (!decision.shouldNotify && syncOk && glucose) {
    decision = evaluateReading({
      glucoseMgdl: glucose.value,
      recordedAt: new Date(glucose.recordedAt),
      trendLabel: trendLabel(glucose.trend),
      previousZone: state.zone,
      now,
      lastAlertAt: state.last_pushed_at
        ? new Date(state.last_pushed_at)
        : null,
      lastAlertedRecordedAt: state.last_alerted_recorded_at
        ? new Date(state.last_alerted_recorded_at)
        : null,
      thresholds,
    })
    nextZone = decision.zone
  }

  if (!decision.shouldNotify || !decision.type || !decision.title) {
    if (nextZone !== state.zone) {
      await admin.from('libre_alert_state').upsert({
        user_id: userId,
        zone: nextZone,
        last_pushed_at: state.last_pushed_at,
        last_stale_pushed_at: state.last_stale_pushed_at,
        last_alerted_recorded_at: state.last_alerted_recorded_at,
        updated_at: now.toISOString(),
      })
    }
    return { pushed: false }
  }

  const { data: tokens } = await admin
    .from('device_tokens')
    .select('token, platform')
    .eq('user_id', userId)

  const tokenList = (
    (tokens ?? []) as Array<{ token: string; platform: string | null }>
  ).map((r) => ({ token: r.token, platform: r.platform }))
  if (tokenList.length === 0) {
    return { pushed: false }
  }

  const fcm = await sendFcmToTokens(tokenList, {
    type: decision.type,
    title: decision.title,
    body: decision.body ?? '',
    glucose_mgdl: glucose ? String(glucose.value) : undefined,
    trend: glucose ? trendLabel(glucose.trend) : undefined,
  })

  if (fcm.invalidTokens.length > 0) {
    await admin
      .from('device_tokens')
      .delete()
      .eq('user_id', userId)
      .in('token', fcm.invalidTokens)
  }

  // Only advance debounce when at least one push was actually delivered.
  if (fcm.sent === 0) {
    return { pushed: false, type: decision.type }
  }

  const isStale = decision.type === 'libre_stale'
  await admin.from('libre_alert_state').upsert({
    user_id: userId,
    zone: nextZone,
    last_pushed_at: isStale ? state.last_pushed_at : now.toISOString(),
    last_stale_pushed_at: isStale
      ? now.toISOString()
      : state.last_stale_pushed_at,
    last_alerted_recorded_at: isStale
      ? state.last_alerted_recorded_at
      : glucose?.recordedAt ?? state.last_alerted_recorded_at,
    updated_at: now.toISOString(),
  })

  return { pushed: true, type: decision.type }
}

type ContextProfileRow = {
  timezone: string | null
  libre_alert_hypo_mgdl: number | null
  glucose_context_alerts_enabled: boolean | null
  glucose_context_computed_at: string | null
}

async function runGlucoseContext(
  // deno-lint-ignore no-explicit-any
  admin: any,
  userId: string,
  now: Date,
  glucose: { value: number; trend: number | null } | null,
): Promise<boolean> {
  const { data: profileRow, error } = await admin
    .from('profiles')
    .select(
      'timezone, libre_alert_hypo_mgdl, glucose_context_alerts_enabled, glucose_context_computed_at',
    )
    .eq('id', userId)
    .maybeSingle()
  if (error) throw new Error(error.message)
  const profile = profileRow as ContextProfileRow | null
  if (!profile) return false

  await refreshContextPatterns(admin, userId, now, profile)

  if (!profile.glucose_context_alerts_enabled || !glucose) return false
  return pushContextAlert(admin, userId, now, profile, glucose)
}

async function refreshContextPatterns(
  // deno-lint-ignore no-explicit-any
  admin: any,
  userId: string,
  now: Date,
  profile: ContextProfileRow,
): Promise<void> {
  const computedAt = profile.glucose_context_computed_at
    ? new Date(profile.glucose_context_computed_at)
    : null
  const fresh = computedAt != null &&
    now.getTime() - computedAt.getTime() < RECOMPUTE_HOURS * 60 * 60 * 1000
  if (fresh) return

  const since = new Date(
    now.getTime() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000,
  )
  const samples = await listGlucoseSince(admin, userId, since.toISOString())
  const patterns = detectPatterns({
    samples: samples.map((row) => ({
      glucoseMgdl: row.glucose_mgdl,
      recordedAt: new Date(row.recorded_at),
    })),
    timezone: profile.timezone ?? 'America/Sao_Paulo',
    now,
    hypoMgdl: profile.libre_alert_hypo_mgdl ?? 70,
  })

  const { error: deleteError } = await admin
    .from('glucose_context_patterns')
    .delete()
    .eq('user_id', userId)
  if (deleteError) throw new Error(deleteError.message)

  if (patterns.length > 0) {
    const { error: insertError } = await admin
      .from('glucose_context_patterns')
      .insert(patterns.map((pattern) => patternRow(userId, now, pattern)))
    if (insertError) throw new Error(insertError.message)
  }

  const { error: stampError } = await admin
    .from('profiles')
    .update({ glucose_context_computed_at: now.toISOString() })
    .eq('id', userId)
  if (stampError) throw new Error(stampError.message)
}

function patternRow(userId: string, now: Date, pattern: ContextPattern) {
  return {
    user_id: userId,
    weekday: pattern.weekday,
    hour: pattern.hour,
    median_mgdl: pattern.medianMgdl,
    median_drop_mgdl: pattern.medianDropMgdl,
    occurrences: pattern.occurrences,
    drop_rate: Number(pattern.dropRate.toFixed(3)),
    suggest_carbs_g: pattern.suggestCarbsG,
    computed_at: now.toISOString(),
  }
}

async function listGlucoseSince(
  // deno-lint-ignore no-explicit-any
  admin: any,
  userId: string,
  sinceIso: string,
): Promise<Array<{ glucose_mgdl: number; recorded_at: string }>> {
  const page = 1000
  const out: Array<{ glucose_mgdl: number; recorded_at: string }> = []
  for (let from = 0; ; from += page) {
    const { data, error } = await admin
      .from('glicemias')
      .select('glucose_mgdl, recorded_at')
      .eq('user_id', userId)
      .gte('recorded_at', sinceIso)
      .order('recorded_at', { ascending: true })
      .range(from, from + page - 1)
    if (error) throw new Error(error.message)
    const rows = (data ?? []) as Array<{
      glucose_mgdl: number
      recorded_at: string
    }>
    out.push(...rows)
    if (rows.length < page) break
  }
  return out
}

async function pushContextAlert(
  // deno-lint-ignore no-explicit-any
  admin: any,
  userId: string,
  now: Date,
  profile: ContextProfileRow,
  glucose: { value: number; trend: number | null },
): Promise<boolean> {
  const timeZone = safeTimeZone(profile.timezone)
  const { data: patternRows, error: patternError } = await admin
    .from('glucose_context_patterns')
    .select(
      'weekday, hour, median_mgdl, median_drop_mgdl, occurrences, drop_rate, suggest_carbs_g',
    )
    .eq('user_id', userId)
  if (patternError) throw new Error(patternError.message)

  const patterns: ContextPattern[] = (
    (patternRows ?? []) as Array<Record<string, unknown>>
  ).map((row) => ({
    weekday: Number(row.weekday),
    hour: Number(row.hour),
    medianMgdl: Number(row.median_mgdl),
    medianDropMgdl: Number(row.median_drop_mgdl),
    occurrences: Number(row.occurrences),
    dropRate: Number(row.drop_rate),
    suggestCarbsG: row.suggest_carbs_g == null
      ? null
      : Number(row.suggest_carbs_g),
  }))
  if (patterns.length === 0) return false

  const { data: stateRows, error: stateError } = await admin
    .from('glucose_context_alert_state')
    .select('weekday, hour, last_notified_on')
    .eq('user_id', userId)
  if (stateError) throw new Error(stateError.message)

  const lastNotifiedOn: Record<string, string> = {}
  for (const row of (stateRows ?? []) as Array<Record<string, unknown>>) {
    const notified = String(row.last_notified_on).slice(0, 10)
    lastNotifiedOn[`${row.weekday}|${row.hour}`] = notified
  }

  const mealSince = new Date(
    now.getTime() - MEAL_QUIET_MINUTES * 60 * 1000,
  ).toISOString()
  const { data: meals, error: mealError } = await admin
    .from('entries')
    .select('id')
    .eq('user_id', userId)
    .gte('recorded_at', mealSince)
    .limit(1)
  if (mealError) throw new Error(mealError.message)

  const decision = evaluateAlert({
    patterns,
    now: zonedParts(now, timeZone),
    currentMgdl: glucose.value,
    hypoMgdl: profile.libre_alert_hypo_mgdl ?? 70,
    trend: glucose.trend,
    recentMeal: (meals?.length ?? 0) > 0,
    lastNotifiedOn,
  })
  if (!decision) return false

  const { data: tokens } = await admin
    .from('device_tokens')
    .select('token, platform')
    .eq('user_id', userId)
  const tokenList = (
    (tokens ?? []) as Array<{ token: string; platform: string | null }>
  ).map((row) => ({ token: row.token, platform: row.platform }))
  if (tokenList.length === 0) return false

  const fcm = await sendFcmToTokens(tokenList, {
    type: 'glucose_context',
    title: decision.title,
    body: decision.body,
    glucose_mgdl: String(glucose.value),
  })
  if (fcm.invalidTokens.length > 0) {
    await admin
      .from('device_tokens')
      .delete()
      .eq('user_id', userId)
      .in('token', fcm.invalidTokens)
  }
  if (fcm.sent === 0) return false

  const { error: upsertError } = await admin
    .from('glucose_context_alert_state')
    .upsert({
      user_id: userId,
      weekday: decision.pattern.weekday,
      hour: decision.pattern.hour,
      last_notified_on: decision.slotDate,
    })
  if (upsertError) throw new Error(upsertError.message)
  return true
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST' && req.method !== 'GET') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const expectedAuth = Deno.env.get('LIBRELINKUP_CRON_SECRET')
    if (!expectedAuth) {
      console.error('LIBRELINKUP_CRON_SECRET not configured')
      return json({ error: 'Server misconfigured' }, 500)
    }

    const authHeader = req.headers.get('Authorization') ?? ''
    const bearer = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7)
      : authHeader
    if (bearer !== expectedAuth) {
      return json({ error: 'Unauthorized' }, 401)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!serviceKey) {
      return json({ error: 'SUPABASE_SERVICE_ROLE_KEY não configurada' }, 500)
    }

    const admin = createClient(supabaseUrl, serviceKey)
    const { data: rows, error } = await admin
      .from('librelinkup_credentials')
      .select('user_id')

    if (error) {
      return json({ error: error.message }, 500)
    }

    const userIds = (rows ?? []).map((row) => row.user_id as string)
    const supporterIds = new Set<string>()
    if (userIds.length > 0) {
      const { data: profiles, error: profileError } = await admin
        .from('profiles')
        .select('id, supporter_status')
        .in('id', userIds)
      if (profileError) {
        return json({ error: profileError.message }, 500)
      }
      for (const profile of profiles ?? []) {
        if (isSupporterStatus(profile.supporter_status as string | null)) {
          supporterIds.add(profile.id as string)
        }
      }
    }

    const results: Array<{
      user_id: string
      ok: boolean
      error?: string
      skipped?: boolean
      pushed?: boolean
      push_type?: string
      context_pushed?: boolean
    }> = []

    for (const row of rows ?? []) {
      const userId = row.user_id as string
      if (!supporterIds.has(userId)) {
        results.push({
          user_id: userId,
          ok: false,
          skipped: true,
          error: 'Apoio inativo',
        })
        continue
      }
      const sync = await syncUserGlucose(admin, userId)
      const now = new Date()
      const result: {
        user_id: string
        ok: boolean
        error?: string
        pushed?: boolean
        push_type?: string
        context_pushed?: boolean
      } = sync.ok
        ? { user_id: userId, ok: true }
        : { user_id: userId, ok: false, error: sync.error }
      if (sync.ok) {
        const push = await pushAlertsForUser(admin, userId, true, {
          value: sync.glucose.value,
          trend: sync.glucose.trend,
          recordedAt: sync.glucose.recordedAt,
        })
        result.pushed = push.pushed
        result.push_type = push.type
      } else {
        const push = await pushAlertsForUser(admin, userId, false, null)
        result.pushed = push.pushed
        result.push_type = push.type
      }
      try {
        result.context_pushed = await runGlucoseContext(
          admin,
          userId,
          now,
          sync.ok
            ? { value: sync.glucose.value, trend: sync.glucose.trend }
            : null,
        )
      } catch (contextError) {
        console.error('glucose context', userId, contextError)
      }
      results.push(result)
    }

    const okCount = results.filter((r) => r.ok).length
    const pushedCount = results.filter((r) => r.pushed).length
    return json({
      synced: okCount,
      pushed: pushedCount,
      total: results.length,
      results,
    })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    return json({ error: message }, 500)
  }
})
