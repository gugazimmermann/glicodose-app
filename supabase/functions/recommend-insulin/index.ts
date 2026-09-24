// Hybrid bolus: GPT estimates carbs via TACO; formula uses day/night target
// in the patient's profile timezone (default America/Sao_Paulo).
// Deploy: supabase functions deploy recommend-insulin

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type RatioSegment = { start_minute: number; value: number }

type Profile = {
  diabetes_type: string | null
  target_glucose_mgdl: number | null
  target_night_mgdl: number | null
  night_start_minute: number | null
  night_end_minute: number | null
  timezone: string | null
  isf_mgdl_per_u: number | null
  ic_ratio: number | null
  isf_schedule: RatioSegment[] | null
  ic_schedule: RatioSegment[] | null
  rapid_insulin_name: string | null
  dose_step: number | null
}

const MAX_RATIO_SEGMENTS = 12

function parseRatioSchedule(raw: unknown): RatioSegment[] {
  if (!Array.isArray(raw)) return []
  const out: RatioSegment[] = []
  for (const e of raw) {
    if (e == null || typeof e !== 'object') continue
    const row = e as Record<string, unknown>
    const start = Number(row.start_minute)
    const value = Number(row.value)
    if (!Number.isFinite(start) || !Number.isFinite(value) || value <= 0) {
      continue
    }
    out.push({
      start_minute: Math.max(0, Math.min(1439, Math.round(start))),
      value,
    })
    if (out.length >= MAX_RATIO_SEGMENTS) break
  }
  return out.sort((a, b) => a.start_minute - b.start_minute)
}

function normalizeRatioSchedule(
  raw: RatioSegment[],
  fallback?: number | null,
): RatioSegment[] {
  const byStart = new Map<number, RatioSegment>()
  for (const s of raw) {
    if (!byStart.has(s.start_minute)) byStart.set(s.start_minute, s)
  }
  let list = [...byStart.values()].sort(
    (a, b) => a.start_minute - b.start_minute,
  )
  if (
    list.length === 0 &&
    fallback != null &&
    Number.isFinite(fallback) &&
    fallback > 0
  ) {
    list = [{ start_minute: 0, value: fallback }]
  }
  if (list.length > 0 && list[0].start_minute !== 0) {
    const midnight =
      fallback != null && Number.isFinite(fallback) && fallback > 0
        ? fallback
        : list[0].value
    list = [{ start_minute: 0, value: midnight }, ...list]
  }
  return list
}

function formatMinuteHm(minute: number): string {
  const m = ((minute % 1440) + 1440) % 1440
  const h = Math.floor(m / 60)
  const min = m % 60
  return `${String(h).padStart(2, '0')}:${String(min).padStart(2, '0')}`
}

function resolveRatio(
  schedule: RatioSegment[],
  minuteOfDay: number,
  fallback?: number | null,
): { value: number; range_label: string } | null {
  const minute = ((Math.round(minuteOfDay) % 1440) + 1440) % 1440
  const normalized = normalizeRatioSchedule(schedule, fallback)
  if (normalized.length === 0) {
    if (fallback != null && Number.isFinite(fallback) && fallback > 0) {
      return { value: fallback, range_label: '00:00–24:00' }
    }
    return null
  }
  let active = normalized[0]
  for (const s of normalized) {
    if (s.start_minute <= minute) active = s
    else break
  }
  const idx = normalized.indexOf(active)
  const end =
    idx + 1 < normalized.length ? normalized[idx + 1].start_minute : 1440
  const endLabel = end >= 1440 ? '24:00' : formatMinuteHm(end)
  return {
    value: active.value,
    range_label: `${formatMinuteHm(active.start_minute)}–${endLabel}`,
  }
}

function hasUsableRatio(
  schedule: RatioSegment[],
  scalar: number | null,
): boolean {
  return (
    normalizeRatioSchedule(schedule, scalar).length > 0 ||
    (scalar != null && Number.isFinite(scalar) && scalar > 0)
  )
}

/** GPT-4o approx USD per 1M tokens (input / output) — observability only */
const GPT4O_INPUT_PER_M = 2.5
const GPT4O_OUTPUT_PER_M = 10

function estimateCostUsd(promptTokens: number, completionTokens: number) {
  return (
    (promptTokens / 1_000_000) * GPT4O_INPUT_PER_M +
    (completionTokens / 1_000_000) * GPT4O_OUTPUT_PER_M
  )
}

async function logAiUsage(opts: {
  supabaseUrl: string
  serviceKey: string | undefined
  userId: string
  model: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
  success: boolean
  errorMessage?: string
  meta?: Record<string, unknown>
}) {
  if (!opts.serviceKey) {
    console.error('ai_usage_logs: SUPABASE_SERVICE_ROLE_KEY missing')
    return
  }
  try {
    const admin = createClient(opts.supabaseUrl, opts.serviceKey)
    const total = opts.promptTokens + opts.completionTokens
    const { error } = await admin.from('ai_usage_logs').insert({
      function_name: 'recommend-insulin',
      user_id: opts.userId,
      model: opts.model,
      prompt_tokens: opts.promptTokens,
      completion_tokens: opts.completionTokens,
      total_tokens: total,
      latency_ms: opts.latencyMs,
      success: opts.success,
      error_message: opts.errorMessage ?? null,
      estimated_cost_usd: estimateCostUsd(
        opts.promptTokens,
        opts.completionTokens,
      ),
      meta: opts.meta ?? {},
    })
    if (error) {
      console.error('ai_usage_logs insert failed:', error.message)
    }
  } catch (err) {
    // Observability must not break the dose path
    console.error('ai_usage_logs insert threw:', err)
  }
}

function normalizeConfidence(raw: unknown): 'baixa' | 'media' | 'alta' {
  const v = String(raw ?? '').toLowerCase().trim()
  if (v === 'baixa' || v === 'low') return 'baixa'
  if (v === 'alta' || v === 'high') return 'alta'
  return 'media'
}

function roundToStep(value: number, step: number): number {
  if (step <= 0) return Math.max(0, Math.round(value))
  const rounded = Math.round(value / step) * step
  return Math.max(0, Math.round(rounded))
}

function computeBolus(opts: {
  glucose: number
  carbs: number
  target: number
  isf: number
  ic: number
  iob: number
  doseStep: number
}) {
  const carbs = Math.max(0, Math.round(opts.carbs))
  const correcao = Math.max(
    0,
    Math.round((opts.glucose - opts.target) / opts.isf),
  )
  const bolusComida = Math.max(0, Math.round(carbs / opts.ic))
  const doseBruta = correcao + bolusComida
  const iob = Math.max(0, Math.round(opts.iob))
  const doseFinal = roundToStep(doseBruta - iob, opts.doseStep)
  return { carbs, correcao, bolusComida, doseBruta, doseFinal, iob }
}

/** Wall-clock parts in an IANA timezone (fallback America/Sao_Paulo). */
function zonedNowParts(timeZone: string, date = new Date()) {
  const zone = timeZone?.trim() || 'America/Sao_Paulo'
  let fmt: Intl.DateTimeFormat
  try {
    fmt = new Intl.DateTimeFormat('en-GB', {
      timeZone: zone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
  } catch (_) {
    fmt = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'America/Sao_Paulo',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
  }
  const parts = fmt.formatToParts(date)
  const hour = Number(parts.find((p) => p.type === 'hour')?.value ?? '0')
  const minute = Number(parts.find((p) => p.type === 'minute')?.value ?? '0')
  const hm = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`
  return { hour, minute, minuteOfDay: hour * 60 + minute, hm, timeZone: zone }
}

function isNightWindow(
  minuteOfDay: number,
  nightStart: number,
  nightEnd: number,
): boolean {
  if (nightStart === nightEnd) return false
  if (nightStart < nightEnd) {
    return minuteOfDay >= nightStart && minuteOfDay <= nightEnd
  }
  return minuteOfDay >= nightStart || minuteOfDay <= nightEnd
}

function diabetesLabel(type: string | null): string {
  switch (type) {
    case 'type_1':
      return 'tipo 1'
    case 'type_2':
      return 'tipo 2'
    case 'other':
      return 'outro'
    default:
      return type ?? 'não informado'
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const openaiKey = Deno.env.get('OPENAI_API_KEY')
    if (!openaiKey) {
      return json({ error: 'OPENAI_API_KEY não configurada' }, 500)
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return json({ error: 'Não autenticado' }, 401)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()
    if (userError || !user) {
      return json({ error: 'Sessão inválida' }, 401)
    }

    const body = await req.json()
    const glucose = Number(body.glucose_mgdl)
    const foodText = (body.food_text as string | null | undefined)?.trim() || null
    const foodImageUrl = (body.food_image_url as string | null | undefined) || null
    const iobU = Math.max(0, Number(body.iob_u) || 0)

    if (!Number.isFinite(glucose) || glucose <= 0) {
      return json({ error: 'glicose inválida' }, 400)
    }
    if (!foodText && !foodImageUrl) {
      return json({ error: 'Informe alimento em texto e/ou foto' }, 400)
    }

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select(
        'diabetes_type, target_glucose_mgdl, target_night_mgdl, night_start_minute, night_end_minute, timezone, isf_mgdl_per_u, ic_ratio, isf_schedule, ic_schedule, rapid_insulin_name, dose_step',
      )
      .eq('id', user.id)
      .maybeSingle()

    if (profileError) {
      return json({ error: profileError.message }, 500)
    }

    const p = profile as Profile | null
    const isfSchedule = parseRatioSchedule(p?.isf_schedule)
    const icSchedule = parseRatioSchedule(p?.ic_schedule)
    if (
      !p ||
      p.target_glucose_mgdl == null ||
      p.target_night_mgdl == null ||
      !hasUsableRatio(isfSchedule, p.isf_mgdl_per_u) ||
      !hasUsableRatio(icSchedule, p.ic_ratio) ||
      !p.rapid_insulin_name
    ) {
      return json({
        error:
          'Perfil incompleto. Cadastre FSI, I:C, meta dia/noite e insulina.',
      }, 400)
    }

    const rawStep = Number(p.dose_step)
    const doseStep = Number.isFinite(rawStep) && rawStep > 0 ? rawStep : 1
    const nightStart = Number(p.night_start_minute ?? 1200)
    const nightEnd = Number(p.night_end_minute ?? 359)

    const bodyTz =
      typeof body.timezone === 'string' ? (body.timezone as string).trim() : ''
    const profileTz = (p.timezone ?? '').trim()
    const timeZone = profileTz || bodyTz || 'America/Sao_Paulo'

    const zoned = zonedNowParts(timeZone)
    const night = isNightWindow(zoned.minuteOfDay, nightStart, nightEnd)
    const target = night
      ? Number(p.target_night_mgdl)
      : Number(p.target_glucose_mgdl)
    const periodo = night ? 'noite' : 'dia'
    const tipo = diabetesLabel(p.diabetes_type ?? 'type_1')

    const isfResolved = resolveRatio(
      isfSchedule,
      zoned.minuteOfDay,
      p.isf_mgdl_per_u,
    )!
    const icResolved = resolveRatio(
      icSchedule,
      zoned.minuteOfDay,
      p.ic_ratio,
    )!
    const isf = isfResolved.value
    const ic = icResolved.value

    const prompt = `Paciente com diabetes ${tipo}. Sempre faça contagem de carboidratos da refeição, conforme composição alimentar.

Use a tabela TACO (Tabela Brasileira de Composição de Alimentos) como referência principal para estimar carboidratos em gramas.
Horário no fuso do paciente (${zoned.timeZone}): ${zoned.hm}.

Refeição (texto): ${foodText ?? 'não informado'}
Foto do alimento/rótulo: ${foodImageUrl ? 'anexada' : 'não informada'}

Não calcule insulina. Responda SOMENTE JSON válido, sem markdown:
{"carboidratos_g": number, "confianca": "baixa|media|alta", "observacao": "string curta sobre a estimativa TACO"}`

    type ContentPart =
      | { type: 'text'; text: string }
      | { type: 'image_url'; image_url: { url: string } }

    const content: ContentPart[] = [{ type: 'text', text: prompt }]
    if (foodImageUrl) {
      content.push({
        type: 'image_url',
        image_url: { url: foodImageUrl },
      })
    }

    const model = 'gpt-4o'
    const startedAt = Date.now()
    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content:
              'Você estima carboidratos em gramas usando a tabela TACO (Brasil). Inclua confianca (baixa|media|alta). Não calcule insulina. Responda só JSON.',
          },
          { role: 'user', content },
        ],
      }),
    })

    const latencyMs = Date.now() - startedAt
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!openaiRes.ok) {
      const errText = await openaiRes.text()
      await logAiUsage({
        supabaseUrl,
        serviceKey,
        userId: user.id,
        model,
        promptTokens: 0,
        completionTokens: 0,
        latencyMs,
        success: false,
        errorMessage: errText.slice(0, 500),
      })
      return json({ error: `OpenAI: ${errText}` }, 502)
    }

    const openaiJson = await openaiRes.json()
    const usage = openaiJson.usage ?? {}
    const promptTokens = Number(usage.prompt_tokens) || 0
    const completionTokens = Number(usage.completion_tokens) || 0

    const rawContent = openaiJson.choices?.[0]?.message?.content
    if (!rawContent || typeof rawContent !== 'string') {
      await logAiUsage({
        supabaseUrl,
        serviceKey,
        userId: user.id,
        model,
        promptTokens,
        completionTokens,
        latencyMs,
        success: false,
        errorMessage: 'empty response',
      })
      return json({ error: 'Resposta vazia da OpenAI' }, 502)
    }

    let parsed: Record<string, unknown>
    try {
      parsed = JSON.parse(rawContent)
    } catch {
      await logAiUsage({
        supabaseUrl,
        serviceKey,
        userId: user.id,
        model,
        promptTokens,
        completionTokens,
        latencyMs,
        success: false,
        errorMessage: 'invalid json',
      })
      return json({ error: 'JSON inválido da OpenAI', raw: rawContent }, 502)
    }

    const carbsRaw = Number(parsed.carboidratos_g)
    if (!Number.isFinite(carbsRaw) || carbsRaw < 0) {
      await logAiUsage({
        supabaseUrl,
        serviceKey,
        userId: user.id,
        model,
        promptTokens,
        completionTokens,
        latencyMs,
        success: false,
        errorMessage: 'invalid carbs',
      })
      return json({ error: 'carboidratos_g inválido', raw: parsed }, 502)
    }

    const confianca = normalizeConfidence(parsed.confianca)

    const { carbs, correcao, bolusComida, doseBruta, doseFinal, iob } =
      computeBolus({
        glucose,
        carbs: carbsRaw,
        target,
        isf,
        ic,
        iob: iobU,
        doseStep,
      })

    let observacao =
      typeof parsed.observacao === 'string' ? parsed.observacao : ''
    if (iob > 0 && doseFinal === 0) {
      observacao =
        observacao ||
        `IOB de ${iob} U cobre a dose bruta (${doseBruta} U); recomendação 0 U.`
    }

    await logAiUsage({
      supabaseUrl,
      serviceKey,
      userId: user.id,
      model,
      promptTokens,
      completionTokens,
      latencyMs,
      success: true,
      meta: { confianca, carbs },
    })

    return json({
      carboidratos_g: carbs,
      confianca,
      correcao_u: correcao,
      bolus_comida_u: bolusComida,
      iob_u: iob,
      insulina_recomendada_u: doseFinal,
      dose_bruta_u: doseBruta,
      dose_step: doseStep,
      meta_mgdl: target,
      meta_periodo: periodo,
      horario_br: zoned.hm,
      isf_aplicado: isf,
      ic_aplicado: ic,
      isf_faixa: isfResolved.range_label,
      ic_faixa: icResolved.range_label,
      observacao,
      source: 'ai',
    })
  } catch (error) {
    return json({ error: String(error) }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
