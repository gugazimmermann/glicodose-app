// Background sync for all connected LibreLinkUp users (cron every ~5 min).
// Deploy:
//   supabase secrets set LIBRELINKUP_CRON_SECRET='um-segredo-longo'
//   supabase functions deploy librelinkup-cron
//
// verify_jwt = false. Authenticate via Authorization: Bearer <LIBRELINKUP_CRON_SECRET>.

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

    const results: Array<{ user_id: string; ok: boolean; error?: string }> = []
    for (const row of rows ?? []) {
      const userId = row.user_id as string
      const sync = await syncUserGlucose(admin, userId)
      if (sync.ok) {
        results.push({ user_id: userId, ok: true })
      } else {
        results.push({ user_id: userId, ok: false, error: sync.error })
      }
    }

    const okCount = results.filter((r) => r.ok).length
    return json({
      synced: okCount,
      total: results.length,
      results,
    })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    return json({ error: message }, 500)
  }
})
