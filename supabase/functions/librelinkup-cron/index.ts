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
    .select('token')
    .eq('user_id', userId)

  const tokenList = ((tokens ?? []) as Array<{ token: string }>).map(
    (r) => r.token,
  )
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

    const results: Array<{
      user_id: string
      ok: boolean
      error?: string
      pushed?: boolean
      push_type?: string
    }> = []

    for (const row of rows ?? []) {
      const userId = row.user_id as string
      const sync = await syncUserGlucose(admin, userId)
      if (sync.ok) {
        const push = await pushAlertsForUser(admin, userId, true, {
          value: sync.glucose.value,
          trend: sync.glucose.trend,
          recordedAt: sync.glucose.recordedAt,
        })
        results.push({
          user_id: userId,
          ok: true,
          pushed: push.pushed,
          push_type: push.type,
        })
      } else {
        const push = await pushAlertsForUser(admin, userId, false, null)
        results.push({
          user_id: userId,
          ok: false,
          error: sync.error,
          pushed: push.pushed,
          push_type: push.type,
        })
      }
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
