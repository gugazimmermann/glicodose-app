/** Shared LibreLinkUp (unofficial) client helpers for Edge Functions. */

export const LIBRE_VERSION = '4.16.0'
export const LIBRE_PRODUCT = 'llu.android'

const REGION_BASE: Record<string, string> = {
  global: 'https://api.libreview.io',
  us: 'https://api-us.libreview.io',
  eu: 'https://api-eu.libreview.io',
  eu2: 'https://api-eu2.libreview.io',
  de: 'https://api-de.libreview.io',
  fr: 'https://api-fr.libreview.io',
  jp: 'https://api-jp.libreview.io',
  ap: 'https://api-ap.libreview.io',
  au: 'https://api-au.libreview.io',
  ae: 'https://api-ae.libreview.io',
  ca: 'https://api-ca.libreview.io',
}

export function normalizeRegion(region: string | null | undefined): string {
  const r = (region ?? 'global').trim().toLowerCase()
  if (r === '' || r === 'br') return 'global'
  return REGION_BASE[r] ? r : 'global'
}

export function libreBaseUrl(region: string): string {
  return REGION_BASE[normalizeRegion(region)] ?? REGION_BASE.global
}

export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input)
  const hash = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export function libreHeaders(opts?: {
  token?: string
  accountId?: string
  accountIdHash?: string
}): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    product: LIBRE_PRODUCT,
    version: LIBRE_VERSION,
    'Cache-Control': 'no-cache',
  }
  if (opts?.token) {
    headers.Authorization = `Bearer ${opts.token}`
  }
  if (opts?.accountIdHash) {
    headers['Account-Id'] = opts.accountIdHash
  }
  return headers
}

export type LibreGlucose = {
  value: number
  trend: number | null
  isHigh: boolean
  isLow: boolean
  factoryTimestamp: string | null
  recordedAt: string
  patientId: string
  raw: unknown
}

export type LibreAuth = {
  token: string
  accountId: string
  expiresAt: string | null
  region: string
}

export type LibreLoginResult =
  | { ok: true; auth: LibreAuth }
  | { ok: false; error: string; status: number; redirectRegion?: string }

export async function libreLogin(
  email: string,
  password: string,
  region: string,
): Promise<LibreLoginResult> {
  let currentRegion = normalizeRegion(region)

  for (let attempt = 0; attempt < 3; attempt++) {
    const base = libreBaseUrl(currentRegion)
    const res = await fetch(`${base}/llu/auth/login`, {
      method: 'POST',
      headers: libreHeaders(),
      body: JSON.stringify({ email, password }),
    })

    let data: Record<string, unknown>
    try {
      data = (await res.json()) as Record<string, unknown>
    } catch {
      return {
        ok: false,
        error: 'Resposta inválida do LibreLinkUp',
        status: 502,
      }
    }

    const payload = (data.data ?? data) as Record<string, unknown>
    if (payload.redirect === true && typeof payload.region === 'string') {
      currentRegion = normalizeRegion(payload.region)
      continue
    }

    const step = payload.step as { type?: string } | undefined
    if (step?.type === 'tou' || step?.type === 'pp') {
      return {
        ok: false,
        error:
          'Aceite os termos / política de privacidade no app LibreLinkUp e tente de novo',
        status: 403,
      }
    }
    if (step?.type === 'verifyEmail') {
      return {
        ok: false,
        error: 'Verifique o e-mail da conta LibreLinkUp',
        status: 403,
      }
    }

    const authTicket = payload.authTicket as
      | { token?: string; expires?: number }
      | undefined
    const user = payload.user as { id?: string } | undefined
    const token = authTicket?.token
    const accountId = user?.id

    if (!token || !accountId) {
      const msg =
        (data.message as string | undefined) ||
        'Falha na autenticação LibreLinkUp (e-mail ou senha)'
      return { ok: false, error: msg, status: res.status === 200 ? 401 : res.status }
    }

    let expiresAt: string | null = null
    if (typeof authTicket?.expires === 'number') {
      // Libre may send seconds or milliseconds
      const ms =
        authTicket.expires > 1e12
          ? authTicket.expires
          : authTicket.expires * 1000
      expiresAt = new Date(ms).toISOString()
    }

    return {
      ok: true,
      auth: {
        token,
        accountId,
        expiresAt,
        region: currentRegion,
      },
    }
  }

  return {
    ok: false,
    error: 'Redirecionamento de região LibreLinkUp em loop',
    status: 502,
  }
}

export async function libreFetchConnections(
  auth: Pick<LibreAuth, 'token' | 'accountId' | 'region'>,
): Promise<
  | { ok: true; connections: Array<Record<string, unknown>> }
  | { ok: false; error: string; status: number }
> {
  const accountIdHash = await sha256Hex(auth.accountId)
  const base = libreBaseUrl(auth.region)
  const res = await fetch(`${base}/llu/connections`, {
    method: 'GET',
    headers: libreHeaders({
      token: auth.token,
      accountIdHash,
    }),
  })

  let data: Record<string, unknown>
  try {
    data = (await res.json()) as Record<string, unknown>
  } catch {
    return { ok: false, error: 'Resposta inválida ao listar conexões', status: 502 }
  }

  if (res.status === 401 || res.status === 403) {
    return {
      ok: false,
      error: 'Sessão LibreLinkUp expirada. Reconecte no app.',
      status: 401,
    }
  }

  if (!res.ok) {
    return {
      ok: false,
      error: (data.message as string) || `Erro LibreLinkUp (${res.status})`,
      status: res.status,
    }
  }

  const list = (data.data as Array<Record<string, unknown>> | undefined) ?? []
  return { ok: true, connections: list }
}

function parseLibreTimestamp(raw: unknown): string {
  if (typeof raw === 'string' && raw.trim()) {
    // FactoryTimestamp often like "8/20/2024 3:15:22 PM"
    const d = new Date(raw)
    if (!Number.isNaN(d.getTime())) return d.toISOString()
  }
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    const ms = raw > 1e12 ? raw : raw * 1000
    return new Date(ms).toISOString()
  }
  return new Date().toISOString()
}

export function extractGlucoseFromConnection(
  patient: Record<string, unknown>,
): LibreGlucose | null {
  const measurement = patient.glucoseMeasurement as
    | Record<string, unknown>
    | null
    | undefined
  if (!measurement) return null

  const valueRaw =
    measurement.ValueInMgPerDl ?? measurement.Value ?? measurement.value
  const value = Number(valueRaw)
  if (!Number.isFinite(value) || value <= 0) return null

  const trendRaw = measurement.TrendArrow ?? measurement.trendArrow
  const trendNum = Number(trendRaw)
  const trend =
    Number.isFinite(trendNum) && trendNum >= 1 && trendNum <= 5
      ? Math.round(trendNum)
      : null

  const factoryTimestamp =
    typeof measurement.FactoryTimestamp === 'string'
      ? measurement.FactoryTimestamp
      : typeof measurement.Timestamp === 'string'
        ? measurement.Timestamp
        : null

  const patientId = String(patient.patientId ?? patient.id ?? 'unknown')

  return {
    value: Math.round(value),
    trend,
    isHigh: Boolean(measurement.isHigh),
    isLow: Boolean(measurement.isLow),
    factoryTimestamp,
    recordedAt: parseLibreTimestamp(
      measurement.FactoryTimestamp ?? measurement.Timestamp ?? Date.now(),
    ),
    patientId,
    raw: measurement,
  }
}

export function glucoseExternalId(g: LibreGlucose): string {
  return `${g.patientId}:${g.factoryTimestamp ?? g.recordedAt}`
}
