import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import {
  extractGlucoseFromConnection,
  glucoseExternalId,
  libreFetchConnections,
  type LibreAuth,
  type LibreGlucose,
} from './libre.ts'

export type SyncResult =
  | { ok: true; glucose: LibreGlucose }
  | { ok: false; error: string; status: number }

type CredRow = {
  user_id: string
  email: string
  region: string
  access_token: string
  account_id: string
  token_expires_at: string | null
  patient_id: string | null
}

export async function syncUserGlucose(
  admin: SupabaseClient,
  userId: string,
): Promise<SyncResult> {
  const { data: cred, error: credError } = await admin
    .from('librelinkup_credentials')
    .select(
      'user_id, email, region, access_token, account_id, token_expires_at, patient_id',
    )
    .eq('user_id', userId)
    .maybeSingle()

  if (credError) {
    return { ok: false, error: credError.message, status: 500 }
  }
  if (!cred) {
    return {
      ok: false,
      error: 'LibreLinkUp não conectado',
      status: 404,
    }
  }

  const row = cred as CredRow

  if (row.token_expires_at) {
    const expires = new Date(row.token_expires_at).getTime()
    if (Number.isFinite(expires) && expires < Date.now() - 60_000) {
      await markError(admin, userId, 'Sessão LibreLinkUp expirada. Reconecte no app.')
      return {
        ok: false,
        error: 'Sessão LibreLinkUp expirada. Reconecte no app.',
        status: 401,
      }
    }
  }

  const auth: LibreAuth = {
    token: row.access_token,
    accountId: row.account_id,
    expiresAt: row.token_expires_at,
    region: row.region,
  }

  const connections = await libreFetchConnections(auth)
  if (!connections.ok) {
    await markError(admin, userId, connections.error)
    return connections
  }

  if (connections.connections.length === 0) {
    const msg = 'Nenhum paciente vinculado na conta seguidor do LibreLinkUp'
    await markError(admin, userId, msg)
    return { ok: false, error: msg, status: 404 }
  }

  let patient = connections.connections[0]
  if (row.patient_id) {
    const match = connections.connections.find(
      (c) => String(c.patientId ?? c.id) === row.patient_id,
    )
    if (match) patient = match
  }

  const glucose = extractGlucoseFromConnection(patient)
  if (!glucose) {
    const msg = 'Sem leitura de glicemia disponível no LibreLinkUp'
    await markError(admin, userId, msg)
    return { ok: false, error: msg, status: 404 }
  }

  const externalId = glucoseExternalId(glucose)
  const { error: upsertError } = await admin.from('glicemias').upsert(
    {
      user_id: userId,
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

  if (upsertError) {
    await markError(admin, userId, upsertError.message)
    return { ok: false, error: upsertError.message, status: 500 }
  }

  const now = new Date().toISOString()
  await admin
    .from('librelinkup_credentials')
    .update({
      patient_id: glucose.patientId,
      last_sync_at: now,
      last_error: null,
      updated_at: now,
    })
    .eq('user_id', userId)

  return { ok: true, glucose }
}

async function markError(
  admin: SupabaseClient,
  userId: string,
  message: string,
) {
  try {
    await admin
      .from('librelinkup_credentials')
      .update({
        last_error: message,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
  } catch {
    // ignore
  }
}
