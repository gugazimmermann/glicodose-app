// Connect LibreLinkUp follower account; stores tokens only (no password).
// Deploy: supabase functions deploy librelinkup-connect

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import {
  extractGlucoseFromConnection,
  glucoseExternalId,
  libreFetchConnections,
  libreLogin,
  normalizeRegion,
} from '../_shared/libre.ts'

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Não autenticado' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()
    if (userError || !user) return json({ error: 'Sessão inválida' }, 401)

    const body = await req.json()
    const email = String(body.email ?? '').trim()
    const password = String(body.password ?? '')
    const region = normalizeRegion(body.region)

    if (!email || !password) {
      return json({ error: 'Informe e-mail e senha do LibreLinkUp' }, 400)
    }

    const login = await libreLogin(email, password, region)
    if (!login.ok) {
      return json({ error: login.error }, login.status)
    }

    const connections = await libreFetchConnections(login.auth)
    if (!connections.ok) {
      return json({ error: connections.error }, connections.status)
    }
    if (connections.connections.length === 0) {
      return json(
        {
          error:
            'Nenhum paciente vinculado. Aceite o convite no app LibreLinkUp (conta seguidor).',
        },
        404,
      )
    }

    const patient = connections.connections[0]
    const glucose = extractGlucoseFromConnection(patient)
    const patientId = String(
      patient.patientId ?? patient.id ?? glucose?.patientId ?? '',
    )

    const now = new Date().toISOString()
    const admin = serviceKey
      ? createClient(supabaseUrl, serviceKey)
      : supabase

    const { error: upsertCredError } = await admin
      .from('librelinkup_credentials')
      .upsert(
        {
          user_id: user.id,
          email,
          region: login.auth.region,
          access_token: login.auth.token,
          account_id: login.auth.accountId,
          token_expires_at: login.auth.expiresAt,
          patient_id: patientId || null,
          last_sync_at: glucose ? now : null,
          last_error: null,
          updated_at: now,
        },
        { onConflict: 'user_id' },
      )

    if (upsertCredError) {
      return json({ error: upsertCredError.message }, 500)
    }

    let latest: Record<string, unknown> | null = null
    if (glucose) {
      const externalId = glucoseExternalId(glucose)
      const { error: gErr } = await admin.from('glicemias').upsert(
        {
          user_id: user.id,
          recorded_at: glucose.recordedAt,
          glucose_mgdl: glucose.value,
          trend: glucose.trend,
          is_high: glucose.isHigh,
          is_low: glucose.isLow,
          source: 'librelinkup',
          external_id: externalId,
          raw: glucose.raw,
        },
        { onConflict: 'user_id,external_id' },
      )
      if (gErr) {
        return json({ error: gErr.message }, 500)
      }
      latest = {
        glucose_mgdl: glucose.value,
        trend: glucose.trend,
        is_high: glucose.isHigh,
        is_low: glucose.isLow,
        recorded_at: glucose.recordedAt,
      }
    }

    return json({
      connected: true,
      email,
      region: login.auth.region,
      patient_id: patientId || null,
      latest,
    })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    return json({ error: message }, 500)
  }
})
