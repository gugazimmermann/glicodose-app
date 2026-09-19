# Diabetes App (Flutter + Supabase)

App híbrido Android/iOS para registro de glicose, alimentação (texto, foto ou voz) e estimativa de insulina rápida com base no perfil do usuário e ChatGPT (via Edge Function).

> **Aviso:** a recomendação é estimativa e **não substitui orientação médica**.

## Pré-requisitos

- Flutter SDK
- Projeto no [Supabase](https://supabase.com)
- Chave da [OpenAI](https://platform.openai.com)
- CLI do Supabase (para deploy das funções)

## 1. Banco e Storage

No SQL Editor do Supabase, execute na ordem:

1. [`supabase/migrations/001_init.sql`](supabase/migrations/001_init.sql)
2. [`supabase/migrations/002_r0_iob.sql`](supabase/migrations/002_r0_iob.sql)
3. [`supabase/migrations/003_prescription_profile.sql`](supabase/migrations/003_prescription_profile.sql)

Isso cria `profiles`, `entries`, RLS, bucket `food-photos`, IOB e campos de prescrição (meta dia/noite).

## 2. Edge Functions

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase secrets set OPENAI_API_KEY=sk-sua-chave
supabase functions deploy recommend-insulin
supabase functions deploy transcribe-food
```

| Função | Papel |
| --- | --- |
| `recommend-insulin` | Estima carboidratos (GPT-4o + TACO / Vision) e aplica a fórmula do perfil − IOB |
| `transcribe-food` | Converte áudio do botão **Falar** em texto (Whisper, `language: pt`) |

As duas usam o mesmo secret `OPENAI_API_KEY` e exigem usuário autenticado (`verify_jwt = true`).

## 3. Variáveis de ambiente (`.env`)

1. Copie o exemplo e preencha:

```bash
cp .env.example .env
```

2. Edite o `.env` (valores em Supabase → **Project Settings → API**):

```env
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
REVENUECAT_IOS_API_KEY=appl_...
REVENUECAT_ANDROID_API_KEY=goog_...
```

3. Rode passando o arquivo:

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

**Importante**

- O `.env` **não** deve ir para o git (já está no `.gitignore`).
- **Não** coloque `OPENAI_API_KEY` no `.env` do app — a chave fica só no Supabase:

```bash
supabase secrets set OPENAI_API_KEY=sk-sua-chave
```

### Apoio recorrente (IAP)

Assinaturas opcionais via Apple/Google + RevenueCat. Guia completo:

[`docs/iap-store-setup.md`](docs/iap-store-setup.md)

```bash
# Migration 009 + webhook
# SQL Editor: supabase/migrations/009_supporter_billing.sql
supabase secrets set REVENUECAT_WEBHOOK_AUTH='um-segredo-longo'
supabase functions deploy revenuecat-webhook
```

No perfil do app: seção **Apoiar o GlicoDose** (Android/iOS com keys no `.env`).

Alternativa sem arquivo:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

### Dispositivo físico (USB)

```bash
flutter devices
flutter run -d <device_id> --dart-define-from-file=.env
```

Na primeira gravação por voz, o Android/iOS pedirá permissão de **microfone**.

## Fluxo do usuário

1. Cadastro / login (Supabase Auth)
2. Preencher perfil uma vez: tipo de diabetes, meta dia/noite, FSI, razão I:C, insulina rápida, passo de dose
3. Na tela principal: glicose + alimentação (texto, foto e/ou **Falar**) → **Calcular insulina**
4. Ajustar **Insulina aplicada** se quiser → **Salvar**
5. Consultar **Histórico**

### Botão Falar

1. Toque no microfone no campo de alimentação → grava
2. Toque de novo → para, envia o áudio para `transcribe-food` (Whisper) e preenche o texto
3. Não depende do reconhecimento de voz nativo do Android (SpeechRecognizer)

## Roadmap

Sugestões de produto e releases: ver [`docs/releases/`](docs/releases/).

- Decisão atual: **R0 — IOB / segurança** → [`docs/releases/R0-decision.md`](docs/releases/R0-decision.md)
- Spec + tickets: [`docs/releases/R0-iob-spec.md`](docs/releases/R0-iob-spec.md)

### R0 — o que foi implementado

Após o MVP, rode a migration extra no SQL Editor:

[`supabase/migrations/002_r0_iob.sql`](supabase/migrations/002_r0_iob.sql)

Redeploy da função (IOB + clamp no servidor):

```bash
supabase functions deploy recommend-insulin
```

Inclui: duração da insulina no perfil, banner de IOB na dose, desconto de IOB na recomendação, editar/excluir no histórico, aceite de disclaimer na 1ª vez.

### R1 — cálculo híbrido

Spec: [`docs/releases/R1-hybrid-spec.md`](docs/releases/R1-hybrid-spec.md)

- IA estima **só carboidratos**; dose = fórmula do perfil − IOB
- Modo **Carbs manuais** (sem OpenAI) na tela Dose
- Redeploy da mesma Edge Function após o R1:

```bash
supabase functions deploy recommend-insulin
```

### Prescrição médica (meta dia/noite + TACO)

Migration:

[`supabase/migrations/003_prescription_profile.sql`](supabase/migrations/003_prescription_profile.sql)

- Tipo de diabetes, meta dia/noite, janela (default 20:00–05:59)
- Horário oficial **America/Sao_Paulo**
- IA usa referência **TACO** para carbs

```bash
# SQL Editor: rode 003_prescription_profile.sql
supabase functions deploy recommend-insulin
```

No app, preencha o perfil (ex.: I:C 25, FSI 150, meta 110 / noite 120).

### Entrada por voz (Whisper)

```bash
supabase functions deploy transcribe-food
```

No app: microfone no campo de alimento → grava → Whisper → texto.

## Estrutura

```
lib/
  config/          # Supabase + RevenueCat + product IDs
  models/          # Profile, Entry
  services/        # Auth, Profile, Entry, Insulin, Speech, Support
  screens/         # Login, Profile, Home, History
  widgets/         # SupportSection, …
supabase/
  migrations/      # SQL (incl. 009_supporter_billing)
  functions/       # recommend-insulin, transcribe-food, revenuecat-webhook
docs/
  iap-store-setup.md  # Produtos Apple/Google + RevenueCat + testes sandbox
```
