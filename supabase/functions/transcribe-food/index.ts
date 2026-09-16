// Transcribe short food descriptions via OpenAI Whisper.
// Deploy: supabase functions deploy transcribe-food

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
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
    const audioBase64 = (body.audio_base64 as string | undefined)?.trim()
    const mimeType =
      (body.mime_type as string | undefined)?.trim() || 'audio/mp4'
    const fileName =
      (body.file_name as string | undefined)?.trim() || 'food.m4a'

    if (!audioBase64) {
      return json({ error: 'Áudio ausente' }, 400)
    }

    let bytes: Uint8Array
    try {
      bytes = decodeBase64(audioBase64)
    } catch {
      return json({ error: 'Áudio inválido' }, 400)
    }

    if (bytes.byteLength < 64) {
      return json({ error: 'Áudio muito curto' }, 400)
    }
    if (bytes.byteLength > 10 * 1024 * 1024) {
      return json({ error: 'Áudio muito grande' }, 400)
    }

    const form = new FormData()
    form.append(
      'file',
      new Blob([bytes], { type: mimeType }),
      fileName,
    )
    form.append('model', 'whisper-1')
    form.append('language', 'pt')
    form.append('response_format', 'json')

    const openaiRes = await fetch(
      'https://api.openai.com/v1/audio/transcriptions',
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${openaiKey}` },
        body: form,
      },
    )

    if (!openaiRes.ok) {
      const errText = await openaiRes.text()
      console.error('whisper error', openaiRes.status, errText)
      return json({ error: 'Falha ao transcrever áudio' }, 502)
    }

    const openaiJson = await openaiRes.json()
    const text =
      typeof openaiJson.text === 'string' ? openaiJson.text.trim() : ''
    if (!text) {
      return json({ error: 'Nenhuma fala reconhecida' }, 422)
    }

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
