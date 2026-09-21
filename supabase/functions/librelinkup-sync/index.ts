// Sync latest LibreLinkUp glucose for the authenticated user.
// Deploy: supabase functions deploy librelinkup-sync

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { syncUserGlucose } from '../_shared/libre_sync.ts'

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
    if (!serviceKey) {
      return json({ error: 'SUPABASE_SERVICE_ROLE_KEY não configurada' }, 500)
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()
    if (userError || !user) return json({ error: 'Sessão inválida' }, 401)

    const admin = createClient(supabaseUrl, serviceKey)
    const result = await syncUserGlucose(admin, user.id)
    if (!result.ok) {
      return json({ error: result.error }, result.status)
    }

    return json({
      glucose_mgdl: result.glucose.value,
      trend: result.glucose.trend,
      is_high: result.glucose.isHigh,
      is_low: result.glucose.isLow,
      recorded_at: result.glucose.recordedAt,
      patient_id: result.glucose.patientId,
    })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    return json({ error: message }, 500)
  }
})
