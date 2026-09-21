# GlicoDose — App do paciente (Flutter + Supabase)

App híbrido Android/iOS para registro de glicose, alimentação (texto, foto ou voz) e estimativa de insulina rápida com base no perfil prescrito e ChatGPT (via Edge Function).

> **Aviso:** a recomendação é estimativa e **não substitui orientação médica**.

## Funcionalidades

- Dose híbrida: IA estima carboidratos (com **confiança** baixa/média/alta); fórmula do perfil − IOB calcula a insulina
- Ajuste de carbs na tela de resultado e recálculo local
- Favoritos de refeição e avisos de hipoglicemia / dose 0 por IOB
- Insulina basal: registro separado (não entra no IOB rápido) + lembretes locais
- Histórico com gráficos, exportação **CSV/PDF** e relatório para consulta
- Linkar Sensor (LibreLinkUp) com glicose atual na Dose
- Alertas de hipo/hiper/sensor parado via **push FCM** (cron LibreLinkUp)
- Importação de glicose via **Health Connect** (Android) / **HealthKit** (iOS)
- Widget de status na home (IOB / glicose) em Android e iOS
- Fuso horário e tema (sistema/claro/escuro) no perfil, sincronizados no Supabase
- Vínculo com médico por código de 6 caracteres
- Apoiar (IAP via RevenueCat)

## Pré-requisitos

- Flutter SDK
- Projeto no [Supabase](https://supabase.com)
- Chave da [OpenAI](https://platform.openai.com)
- Projeto [Firebase](https://firebase.google.com) (FCM) com `google-services.json` / `GoogleService-Info.plist`
- CLI do Supabase (para deploy das funções)

## 1. Banco e Storage

No SQL Editor do Supabase (ou `supabase db push` a partir desta pasta), execute as migrations na ordem:

1. [`001_init.sql`](supabase/migrations/001_init.sql) … até
2. [`019_libre_alert_same_sample.sql`](supabase/migrations/019_libre_alert_same_sample.sql)

Resumo das migrations recentes:

| Migration | Conteúdo |
| --- | --- |
| `014` | `profiles.timezone` (IANA) |
| `015` | `profiles.theme` (`system` / `light` / `dark`) |
| `016` | Alertas Libre + `device_tokens` + estado de debounce |
| `017` | Insulina basal (`basal_doses` + campos no perfil) |
| `018` | Sync Health Connect / HealthKit (metadados em `entries`) |
| `019` | Debounce de alerta no mesmo sample Libre |

## 2. Edge Functions

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase secrets set OPENAI_API_KEY=sk-sua-chave
supabase secrets set LIBRELINKUP_CRON_SECRET='um-segredo-longo'
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
supabase functions deploy recommend-insulin
supabase functions deploy transcribe-food
supabase functions deploy revenuecat-webhook
supabase functions deploy librelinkup-connect
supabase functions deploy librelinkup-sync
supabase functions deploy librelinkup-cron
```

| Função | Papel |
| --- | --- |
| `recommend-insulin` | Carbs (GPT-4o + TACO / Vision) + confiança; dose = fórmula do perfil (`dose_step`) − IOB; log em `ai_usage_logs` |
| `transcribe-food` | Áudio → texto (Whisper, `language: pt`) |
| `revenuecat-webhook` | Espelha status de apoiador (IAP) em `profiles` |
| `librelinkup-connect` / `sync` | Credenciais e sync sob demanda do LibreLinkUp |
| `librelinkup-cron` | Sync periódico + push FCM de alertas hipo/hiper/stale |

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

**Não** coloque `OPENAI_API_KEY` nem a service account do Firebase no `.env` do app — só nos secrets do Supabase.

### Firebase / FCM

1. Gere os arquivos do app no Firebase Console (ou `flutterfire configure`).
2. Confirme `android/app/google-services.json` e `ios/Runner/GoogleService-Info.plist`.
3. No cron: `FIREBASE_SERVICE_ACCOUNT_JSON` (conta de serviço do mesmo projeto).

### Apoio (IAP)

Guia: [`docs/iap-store-setup.md`](docs/iap-store-setup.md)

```bash
supabase secrets set REVENUECAT_WEBHOOK_AUTH='um-segredo-longo'
supabase functions deploy revenuecat-webhook
```

## Fluxo do usuário

1. Cadastro / login (Supabase Auth)
2. Perfil: tipo de diabetes, meta dia/noite, FSI, I:C, insulina rápida, basal, fuso, tema, alertas Libre, Health
3. Dose: glicose (manual / Libre / Health) + alimento (texto/foto/**Falar**/favorito) → calcular
4. Revisar carbs (confiança IA), confirmar insulina aplicada; registrar basal se for o caso
5. Histórico: lista, gráficos, exportar CSV/PDF
6. Widget / badge / foreground task: IOB ao vivo
7. Perfil: Linkar Sensor, Apoiar, sair

## Roadmap

Specs em [`docs/releases/`](docs/releases/).

| Release | Status |
| --- | --- |
| R0 IOB / disclaimer | Feito |
| R1 híbrido (IA = carbs) | Feito |
| R2 gráficos | Feito |
| R3 export CSV/relatório | Feito |
| R4 LibreLinkUp (Linkar Sensor) | Feito |
| R5 timezone, tema, basal, alertas FCM, Health, widget iOS | Feito |

## Estrutura

```
lib/
  config/          # Supabase + RevenueCat
  models/          # Profile, Entry, BasalDose, InsulinRecommendation, LibreGlucose
  services/        # Auth, Entry, Insulin, IOB, Basal, Libre, Health, FCM, Export, Widget…
  screens/         # Dose, Histórico, Perfil, Health import, Linkar Sensor, Apoiar…
supabase/
  migrations/      # 001 … 019
  functions/       # recommend-insulin, transcribe-food, revenuecat-webhook, librelinkup-*
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
