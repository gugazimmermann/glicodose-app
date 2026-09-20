# GlicoDose — App do paciente (Flutter + Supabase)

App híbrido Android/iOS para registro de glicose, alimentação (texto, foto ou voz) e estimativa de insulina rápida com base no perfil prescrito e ChatGPT (via Edge Function).

> **Aviso:** a recomendação é estimativa e **não substitui orientação médica**.

## Funcionalidades

- Dose híbrida: IA estima carboidratos (com **confiança** baixa/média/alta); fórmula do perfil − IOB calcula a insulina
- Ajuste de carbs na tela de resultado e recálculo local
- Avisos de hipoglicemia e dose 0 por IOB
- Histórico com gráficos, exportação **CSV** e relatório para consulta
- Lembretes diários de glicemia/refeição (notificações locais)
- Vínculo com médico por código de 6 caracteres
- Apoiar (IAP via RevenueCat)
- Stub **Saúde e CGM** (R4 — importação futura)

## Pré-requisitos

- Flutter SDK
- Projeto no [Supabase](https://supabase.com)
- Chave da [OpenAI](https://platform.openai.com)
- CLI do Supabase (para deploy das funções)

## 1. Banco e Storage

No SQL Editor do Supabase (ou `supabase db push` a partir desta pasta), execute as migrations na ordem:

1. [`001_init.sql`](supabase/migrations/001_init.sql) … até
2. [`012_rx_ai_ops.sql`](supabase/migrations/012_rx_ai_ops.sql)

A **012** adiciona: Rx editável ampliada para médicos, audit log de prescrição, `patient_ai_analyses`, `ai_usage_logs`, doações de pacientes no admin e RPC `get_admin_ai_stats`.

Isso cria `profiles`, `entries`, RLS, bucket `food-photos`, IOB, billing e ops de IA.

## 2. Edge Functions

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase secrets set OPENAI_API_KEY=sk-sua-chave
supabase functions deploy recommend-insulin
supabase functions deploy transcribe-food
supabase functions deploy revenuecat-webhook
```

| Função | Papel |
| --- | --- |
| `recommend-insulin` | Carbs (GPT-4o + TACO / Vision) + confiança; dose = fórmula do perfil (`dose_step`) − IOB; log em `ai_usage_logs` |
| `transcribe-food` | Áudio → texto (Whisper, `language: pt`) |
| `revenuecat-webhook` | Espelha status de apoiador (IAP) em `profiles` |

## 3. Variáveis de ambiente (`.env`)

```bash
cp .env.example .env
```

```env
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
REVENUECAT_IOS_API_KEY=appl_...
REVENUECAT_ANDROID_API_KEY=goog_...
```

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

**Não** coloque `OPENAI_API_KEY` no `.env` do app — só no Supabase.

### Apoio (IAP)

Guia: [`docs/iap-store-setup.md`](docs/iap-store-setup.md)

```bash
supabase secrets set REVENUECAT_WEBHOOK_AUTH='um-segredo-longo'
supabase functions deploy revenuecat-webhook
```

## Fluxo do usuário

1. Cadastro / login (Supabase Auth)
2. Perfil: tipo de diabetes, meta dia/noite, FSI, I:C, insulina, passo de dose, duração IOB
3. Dose: glicose + alimento (texto/foto/**Falar**) → calcular
4. Revisar carbs (confiança IA), confirmar insulina aplicada
5. Histórico: lista, gráficos, exportar CSV/relatório
6. Perfil: lembretes, Saúde/CGM (em breve), Apoiar, sair

## Roadmap

Specs em [`docs/releases/`](docs/releases/).

| Release | Status |
| --- | --- |
| R0 IOB / disclaimer | Feito |
| R1 híbrido (IA = carbs) | Feito |
| R2 gráficos | Feito |
| R3 lembretes + export | Feito (esta versão) |
| R4 Health / CGM | Stub no app |

## Estrutura

```
lib/
  config/          # Supabase + RevenueCat
  models/          # Profile, Entry, InsulinRecommendation
  services/        # Auth, Entry, Insulin, IOB, Reminders, Export, Support…
  screens/         # Dose, Histórico, Perfil, Lembretes, Saúde…
supabase/
  migrations/      # 001 … 012
  functions/       # recommend-insulin, transcribe-food, revenuecat-webhook
docs/
  iap-store-setup.md
  releases/
```

## Projetos irmãos

| Repo | Papel |
| --- | --- |
| `diabetes-medicos` | Portal do médico |
| `diabetes-admin` | KPIs + doações + uso de IA |
| `diabetes-site` | Landing + Apoiar (Stripe público) |
