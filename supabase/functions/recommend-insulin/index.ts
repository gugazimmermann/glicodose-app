// Hybrid bolus: GPT estimates carbs via TACO; formula uses day/night target (America/Sao_Paulo).
// Deploy: supabase functions deploy recommend-insulin

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type Profile = {
  diabetes_type: string | null
  target_glucose_mgdl: number | null
  target_night_mgdl: number | null
  night_start_minute: number | null
  night_end_minute: number | null
  isf_mgdl_per_u: number | null
  ic_ratio: number | null
  rapid_insulin_name: string | null
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

/** Brazil official time parts in America/Sao_Paulo */
function brazilNowParts(date = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'America/Sao_Paulo',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
  const parts = fmt.formatToParts(date)
  const hour = Number(parts.find((p) => p.type === 'hour')?.value ?? '0')
  const minute = Number(parts.find((p) => p.type === 'minute')?.value ?? '0')
  const hm = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`
  return { hour, minute, minuteOfDay: hour * 60 + minute, hm }
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
        'diabetes_type, target_glucose_mgdl, target_night_mgdl, night_start_minute, night_end_minute, isf_mgdl_per_u, ic_ratio, rapid_insulin_name',
      )
      .eq('id', user.id)
      .maybeSingle()

    if (profileError) {
      return json({ error: profileError.message }, 500)
    }

    const p = profile as Profile | null
    if (
      !p ||
      p.target_glucose_mgdl == null ||
      p.target_night_mgdl == null ||
      p.isf_mgdl_per_u == null ||
      p.ic_ratio == null ||
      !p.rapid_insulin_name
    ) {
      return json({
        error:
          'Perfil incompleto. Cadastre FSI, I:C, meta dia/noite e insulina.',
      }, 400)
    }

    const doseStep = 1
    const isf = Number(p.isf_mgdl_per_u)
    const ic = Number(p.ic_ratio)
    const nightStart = Number(p.night_start_minute ?? 1200)
    const nightEnd = Number(p.night_end_minute ?? 359)

    const br = brazilNowParts()
    const night = isNightWindow(br.minuteOfDay, nightStart, nightEnd)
    const target = night
      ? Number(p.target_night_mgdl)
      : Number(p.target_glucose_mgdl)
    const periodo = night ? 'noite' : 'dia'
    const tipo = diabetesLabel(p.diabetes_type ?? 'type_1')

    const prompt = `Paciente com diabetes ${tipo}. Sempre faça contagem de carboidratos da refeição, conforme composição alimentar.

Use a tabela TACO (Tabela Brasileira de Composição de Alimentos) como referência principal para estimar carboidratos em gramas.
Horário oficial brasileiro (America/Sao_Paulo): ${br.hm}.

Refeição (texto): ${foodText ?? 'não informado'}
Foto do alimento/rótulo: ${foodImageUrl ? 'anexada' : 'não informada'}

Não calcule insulina. Responda SOMENTE JSON válido, sem markdown:
{"carboidratos_g": number, "observacao": "string curta sobre a estimativa TACO"}`

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

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content:
              'Você estima carboidratos em gramas usando a tabela TACO (Brasil). Não calcule insulina. Responda só JSON.',
          },
          { role: 'user', content },
        ],
      }),
    })

    if (!openaiRes.ok) {
      const errText = await openaiRes.text()
      return json({ error: `OpenAI: ${errText}` }, 502)
    }

    const openaiJson = await openaiRes.json()
    const rawContent = openaiJson.choices?.[0]?.message?.content
    if (!rawContent || typeof rawContent !== 'string') {
      return json({ error: 'Resposta vazia da OpenAI' }, 502)
    }

    let parsed: Record<string, unknown>
    try {
      parsed = JSON.parse(rawContent)
    } catch {
      return json({ error: 'JSON inválido da OpenAI', raw: rawContent }, 502)
    }

    const carbsRaw = Number(parsed.carboidratos_g)
    if (!Number.isFinite(carbsRaw) || carbsRaw < 0) {
      return json({ error: 'carboidratos_g inválido', raw: parsed }, 502)
    }

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

    return json({
      carboidratos_g: carbs,
      correcao_u: correcao,
      bolus_comida_u: bolusComida,
      iob_u: iob,
      insulina_recomendada_u: doseFinal,
      dose_bruta_u: doseBruta,
      meta_mgdl: target,
      meta_periodo: periodo,
      horario_br: br.hm,
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
