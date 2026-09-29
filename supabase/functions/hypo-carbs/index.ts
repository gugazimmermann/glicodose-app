// Names fast-carb portions for grams already computed on the device.
// Does not calculate insulin or change the gram budget.
// Deploy: supabase functions deploy hypo-carbs

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

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
}) {
  if (!opts.serviceKey) return
  try {
    const admin = createClient(opts.supabaseUrl, opts.serviceKey)
    const total = opts.promptTokens + opts.completionTokens
    await admin.from('ai_usage_logs').insert({
      function_name: 'hypo-carbs',
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
      meta: {},
    })
  } catch (err) {
    console.error('ai_usage_logs insert threw:', err)
  }
}

type Portion = {
  alimento: string
  quantidade: string
  carboidratos_g: number
}

function keepWithinBudget(raw: unknown, budget: number): Portion[] {
  if (!Array.isArray(raw)) return []
  const kept: Portion[] = []
  for (const item of raw) {
    if (item == null || typeof item !== 'object') continue
    const row = item as Record<string, unknown>
    const food = typeof row.alimento === 'string' ? row.alimento.trim() : ''
    const quantity = typeof row.quantidade === 'string'
      ? row.quantidade.trim()
      : ''
    const carbs = Math.round(Number(row.carboidratos_g))
    if (!food || !quantity) continue
    if (!Number.isFinite(carbs) || carbs <= 0 || carbs > budget) continue
    kept.push({ alimento: food, quantidade: quantity, carboidratos_g: carbs })
    if (kept.length === 7) break
  }
  return kept
}

function equivalentGuide(budget: number): string {
  const juiceMl = budget * 10
  const honeyG = Math.floor((budget * 20) / 15)
  const honeyCarbs = Math.floor((honeyG * 15) / 20)
  const chocolateG = Math.floor((budget * 100) / 60)
  const chocolateCarbs = Math.floor((chocolateG * 60) / 100)
  const gummyG = Math.floor((budget * 100) / 80)
  const gummyCarbs = Math.floor((gummyG * 80) / 100)
  const gelLine = budget < 15
    ? `Sachê de gel de glicose: 15 g por sachê. Não sugira o sachê inteiro; indique ${budget} g (cerca de três quartos se for 11 g).`
    : `Sachê de gel de glicose: 15 g por sachê. Quantidade máxima: ${budget} g no total, sem passar disso.`
  return `Equivalentes para no máximo ${budget} g de carboidrato. Use somente esta lista e estas quantidades. Não aumente. Não some os itens.

- Suco de laranja: 10 g a cada 100 ml → ${juiceMl} ml (${budget} g)
- Refrigerante comum (não diet, não zero): 10 g a cada 100 ml → ${juiceMl} ml (${budget} g)
- ${gelLine}
- Mel: 15 g de carboidrato em 20 g (1 colher de sopa) → até ${honeyG} g (${honeyCarbs} g de carboidrato)
- Açúcar: 1 g de carboidrato por 1 g → ${budget} g
- Barra de chocolate ao leite: cerca de 60 g de carboidrato em 100 g → até ${chocolateG} g da barra (${chocolateCarbs} g de carboidrato). Absorve mais devagar por causa da gordura.
- Bala de goma: cerca de 80 g de carboidrato em 100 g → até ${gummyG} g (${gummyCarbs} g de carboidrato)`
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
    const budget = Math.round(Number(body.carboidratos_g))
    if (!Number.isFinite(budget) || budget <= 0 || budget > 200) {
      return json({ error: 'carboidratos_g inválido' }, 400)
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
              'Você indica porções equivalentes de carboidrato usando a tabela TACO (Brasil). Use só os alimentos e as quantidades da lista. Não calcule insulina. Não ultrapasse o limite de gramas em nenhuma alternativa. Responda só JSON.',
          },
          {
            role: 'user',
            content: `${equivalentGuide(budget)}

Devolva uma alternativa para cada alimento da lista. Cada uma é uma opção, não um prato somado. Nenhuma pode passar de ${budget} g. Responda SOMENTE JSON: {"porcoes":[{"alimento":"string","quantidade":"string","carboidratos_g":number}]}`,
          },
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
    const rawContent = openaiJson.choices?.[0]?.message?.content
    if (!rawContent || typeof rawContent !== 'string') {
      await logAiUsage({
        supabaseUrl,
        serviceKey,
        userId: user.id,
        model,
        promptTokens: Number(usage.prompt_tokens) || 0,
        completionTokens: Number(usage.completion_tokens) || 0,
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
        promptTokens: Number(usage.prompt_tokens) || 0,
        completionTokens: Number(usage.completion_tokens) || 0,
        latencyMs,
        success: false,
        errorMessage: 'invalid json',
      })
      return json({ error: 'JSON inválido da OpenAI' }, 502)
    }

    const porcoes = keepWithinBudget(parsed.porcoes, budget)
    await logAiUsage({
      supabaseUrl,
      serviceKey,
      userId: user.id,
      model,
      promptTokens: Number(usage.prompt_tokens) || 0,
      completionTokens: Number(usage.completion_tokens) || 0,
      latencyMs,
      success: true,
    })
    return json({ porcoes })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    return json({ error: message }, 500)
  }
})
