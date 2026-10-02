// Describe a food photo in Portuguese via GPT-4o mini vision.
// Deploy: supabase functions deploy describe-food

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

/** GPT-4o mini approx USD per 1M tokens (input / output) — observability only */
const GPT4O_MINI_INPUT_PER_M = 0.15
const GPT4O_MINI_OUTPUT_PER_M = 0.6
const MAX_IMAGE_BYTES = 4 * 1024 * 1024

const ALLOWED_MIME = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
])

function estimateCostUsd(promptTokens: number, completionTokens: number) {
  return (
    (promptTokens / 1_000_000) * GPT4O_MINI_INPUT_PER_M +
    (completionTokens / 1_000_000) * GPT4O_MINI_OUTPUT_PER_M
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
      function_name: 'describe-food',
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
    console.error('ai_usage_logs insert threw:', err)
  }
}

function decodeBase64(b64: string): Uint8Array {
  const cleaned = b64.replace(/^data:[^;]+;base64,/, '').replace(/\s/g, '')
  const binary = atob(cleaned)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
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
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
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
    const imageBase64 = (body.image_base64 as string | undefined)?.trim()
    const mimeType =
      (body.mime_type as string | undefined)?.trim().toLowerCase() ||
      'image/jpeg'

    if (!imageBase64) {
      return json({ error: 'Foto ausente' }, 400)
    }
    if (!ALLOWED_MIME.has(mimeType)) {
      return json({ error: 'Formato de foto não suportado' }, 400)
    }

    let bytes: Uint8Array
    try {
      bytes = decodeBase64(imageBase64)
    } catch {
      return json({ error: 'Foto inválida' }, 400)
    }

    if (bytes.byteLength < 64) {
      return json({ error: 'Foto inválida' }, 400)
    }
    if (bytes.byteLength > MAX_IMAGE_BYTES) {
      return json({ error: 'Foto muito grande' }, 400)
    }

    const cleaned = imageBase64
      .replace(/^data:[^;]+;base64,/, '')
      .replace(/\s/g, '')
    const prompt =
      'Descreva a refeição desta foto em uma frase curta, em português, com os itens visíveis e a porção aproximada quando der para ver. Não estime carboidratos nem insulina. Responda SOMENTE JSON válido, sem markdown: {"descricao":"string"}'

    const model = 'gpt-4o-mini'
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
              'Você descreve refeições em português para um diário alimentar. Uma frase curta, com os itens visíveis e a porção aproximada quando der. Sem carboidratos e sem insulina. Responda só JSON {"descricao":"..."}.',
          },
          {
            role: 'user',
            content: [
              { type: 'text', text: prompt },
              {
                type: 'image_url',
                image_url: { url: `data:${mimeType};base64,${cleaned}` },
              },
            ],
          },
        ],
      }),
    })
    const latencyMs = Date.now() - startedAt

    if (!openaiRes.ok) {
      const errText = await openaiRes.text()
      console.error('describe-food error', openaiRes.status, errText)
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
        meta: { bytes: bytes.byteLength, mime_type: mimeType },
      })
      return json({ error: 'Falha ao descrever a foto' }, 502)
    }

    const openaiJson = await openaiRes.json()
    const usage = openaiJson.usage ?? {}
    const promptTokens = Number(usage.prompt_tokens) || 0
    const completionTokens = Number(usage.completion_tokens) || 0
    const rawContent = openaiJson.choices?.[0]?.message?.content

    let text = ''
    if (typeof rawContent === 'string' && rawContent.trim()) {
      try {
        const parsed = JSON.parse(rawContent) as Record<string, unknown>
        text =
          typeof parsed.descricao === 'string' ? parsed.descricao.trim() : ''
      } catch {
        text = ''
      }
    }

    if (!text) {
      await logAiUsage({
        supabaseUrl,
        serviceKey,
        userId: user.id,
        model,
        promptTokens,
        completionTokens,
        latencyMs,
        success: false,
        errorMessage: 'empty description',
        meta: { bytes: bytes.byteLength, mime_type: mimeType },
      })
      return json({ error: 'Não foi possível descrever a foto' }, 422)
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
      meta: {
        bytes: bytes.byteLength,
        mime_type: mimeType,
        text_len: text.length,
      },
    })

    return json({ text })
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
