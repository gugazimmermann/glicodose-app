/**
 * FCM HTTP v1 sender using a service-account JSON secret.
 * Secret: FIREBASE_SERVICE_ACCOUNT_JSON
 */

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

let cachedToken: { accessToken: string; expiresAt: number } | null = null

function parseServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')
  if (!raw) return null
  try {
    return JSON.parse(raw) as ServiceAccount
  } catch {
    console.error('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON')
    return null
  }
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function base64Url(data: ArrayBuffer | Uint8Array | string): string {
  let bytes: Uint8Array
  if (typeof data === 'string') {
    bytes = new TextEncoder().encode(data)
  } else if (data instanceof Uint8Array) {
    bytes = data
  } else {
    bytes = new Uint8Array(data)
  }
  let binary = ''
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.accessToken
  }

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claim = base64Url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  )
  const unsigned = `${header}.${claim}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  )
  const jwt = `${unsigned}.${base64Url(sig)}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`FCM token exchange failed: ${res.status} ${text}`)
  }
  const json = (await res.json()) as { access_token: string; expires_in: number }
  cachedToken = {
    accessToken: json.access_token,
    expiresAt: now + (json.expires_in ?? 3600),
  }
  return cachedToken.accessToken
}

export type FcmPayload = {
  type: string
  title: string
  body: string
  glucose_mgdl?: string
  trend?: string
}

export type FcmSendResult = {
  sent: number
  failed: number
  invalidTokens: string[]
}

const INVALID_TOKEN_CODES = new Set([
  'UNREGISTERED',
  'NOT_FOUND',
  'INVALID_ARGUMENT',
])

function isInvalidTokenError(body: string): boolean {
  try {
    const parsed = JSON.parse(body) as {
      error?: { details?: Array<{ errorCode?: string }>; status?: string }
    }
    const details = parsed.error?.details ?? []
    for (const d of details) {
      if (d.errorCode && INVALID_TOKEN_CODES.has(d.errorCode)) return true
    }
    const status = parsed.error?.status
    if (status === 'NOT_FOUND') return true
  } catch {
    // fall through
  }
  return (
    body.includes('UNREGISTERED') ||
    body.includes('"errorCode": "NOT_FOUND"') ||
    body.includes('Requested entity was not found')
  )
}

export async function sendFcmToTokens(
  tokens: string[],
  payload: FcmPayload,
): Promise<FcmSendResult> {
  const sa = parseServiceAccount()
  if (!sa || tokens.length === 0) {
    if (!sa) {
      console.error('FIREBASE_SERVICE_ACCOUNT_JSON missing or invalid')
    }
    return { sent: 0, failed: 0, invalidTokens: [] }
  }

  const accessToken = await getAccessToken(sa)
  const url =
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`
  let sent = 0
  let failed = 0
  const invalidTokens: string[] = []

  for (const token of tokens) {
    const body = {
      message: {
        token,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: {
          type: payload.type,
          title: payload.title,
          body: payload.body,
          ...(payload.glucose_mgdl
            ? { glucose_mgdl: payload.glucose_mgdl }
            : {}),
          ...(payload.trend ? { trend: payload.trend } : {}),
        },
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: 'libre_glucose_alerts',
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: {
            aps: {
              sound: 'default',
              'content-available': 1,
            },
          },
        },
      },
    }

    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      })
      if (res.ok) {
        sent++
      } else {
        failed++
        const text = await res.text()
        console.error('FCM send failed', token.slice(0, 12), text)
        if (isInvalidTokenError(text)) {
          invalidTokens.push(token)
        }
      }
    } catch (e) {
      failed++
      console.error('FCM send error', e)
    }
  }

  return { sent, failed, invalidTokens }
}
