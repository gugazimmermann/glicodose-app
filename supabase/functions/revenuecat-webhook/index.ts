// Mirrors RevenueCat subscription events onto public.profiles supporter_* columns.
// Deploy:
//   supabase secrets set REVENUECAT_WEBHOOK_AUTH=your_shared_secret
//   supabase functions deploy revenuecat-webhook
//
// verify_jwt = false (configured in config.toml). Authenticate via Authorization header.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type WebhookBody = {
  api_version?: string
  event: {
    type: string
    app_user_id?: string
    product_id?: string
    new_product_id?: string
    store?: string
    expiration_at_ms?: number | null
    entitlement_ids?: string[] | null
    entitlement_id?: string | null
  }
}

type SupporterStatus = 'none' | 'active' | 'grace' | 'expired' | 'canceled'

function mapStore(store: string | undefined): string | null {
  if (!store) return null
  switch (store.toUpperCase()) {
    case 'APP_STORE':
    case 'MAC_APP_STORE':
      return 'apple'
    case 'PLAY_STORE':
      return 'google'
    case 'AMAZON':
      return 'amazon'
    case 'STRIPE':
      return 'stripe'
    case 'PROMOTIONAL':
      return 'promotional'
    default:
      return 'unknown'
  }
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value)
}

function resolveStatus(type: string): SupporterStatus | null {
  switch (type) {
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'UNCANCELLATION':
    case 'PRODUCT_CHANGE':
    case 'SUBSCRIPTION_EXTENDED':
    case 'NON_RENEWING_PURCHASE':
    case 'TEMPORARY_ENTITLEMENT_GRANT':
    case 'REFUND_REVERSED':
    case 'TEST':
      return 'active'
    case 'BILLING_ISSUE':
      return 'grace'
    case 'CANCELLATION':
      return 'canceled'
    case 'EXPIRATION':
      return 'expired'
    case 'SUBSCRIPTION_PAUSED':
      // Access continues until EXPIRATION; keep current row untouched.
      return null
    default:
      return null
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const expectedAuth = Deno.env.get('REVENUECAT_WEBHOOK_AUTH')
    if (!expectedAuth) {
      console.error('REVENUECAT_WEBHOOK_AUTH not configured')
      return new Response(JSON.stringify({ error: 'Server misconfigured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const authHeader = req.headers.get('Authorization') ?? ''
    const bearer = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7)
      : authHeader
    if (bearer !== expectedAuth) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = (await req.json()) as WebhookBody
    const event = body.event
    if (!event?.type) {
      return new Response(JSON.stringify({ error: 'Invalid payload' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Ignore transfer events (no stable single user mapping here).
    if (event.type === 'TRANSFER') {
      return new Response(JSON.stringify({ ok: true, ignored: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const appUserId = event.app_user_id
    if (!appUserId || !isUuid(appUserId)) {
      // Anonymous / non-Supabase IDs: acknowledge without writing.
      console.log(
        `Skipping supporter sync for non-uuid app_user_id=${appUserId} type=${event.type}`,
      )
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const status = resolveStatus(event.type)
    if (status === null) {
      return new Response(JSON.stringify({ ok: true, ignored: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const productId =
      event.type === 'PRODUCT_CHANGE'
        ? (event.new_product_id ?? event.product_id ?? null)
        : (event.product_id ?? null)

    const expiresAt =
      typeof event.expiration_at_ms === 'number'
        ? new Date(event.expiration_at_ms).toISOString()
        : null

    const patch: Record<string, unknown> = {
      supporter_status: status === 'expired' ? 'expired' : status,
      supporter_updated_at: new Date().toISOString(),
      supporter_store: mapStore(event.store),
    }

    if (productId) {
      patch.supporter_product_id = productId
    }

    if (expiresAt) {
      patch.supporter_expires_at = expiresAt
    }

    if (status === 'expired') {
      // Keep product_id for history; status alone drives UI badge.
      patch.supporter_status = 'expired'
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceKey)

    const { error } = await supabase
      .from('profiles')
      .update(patch)
      .eq('id', appUserId)

    if (error) {
      console.error('profiles update failed', error)
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ ok: true, user: appUserId, status }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  } catch (e) {
    console.error(e)
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : 'Unknown' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})
