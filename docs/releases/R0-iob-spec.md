# R0 — Spec técnico: IOB + edição de registros + disclaimer

**Release:** R0 Segurança  
**Decisão:** [`R0-decision.md`](R0-decision.md)  
**Estimativa:** ~1–1,5 sprint (5–8 dias de 1 dev)  
**Dependências:** MVP atual (auth, profiles, entries, Edge `recommend-insulin`)

---

## 1. Objetivo

Reduzir risco de overdose por doses repetidas e aumentar confiança no diário:

1. Calcular e exibir **IOB** (insulina on board / ativa).
2. Incluir IOB no prompt / resposta de recomendação.
3. Permitir **editar e excluir** entries.
4. Exigir **aceite de disclaimer** uma vez por usuário.

---

## 2. Modelo de IOB (definição de produto)

### Fórmula (linear simples — MVP clínico-pessoal)

Para cada dose aplicada `A` no horário `T`, com duração `D` horas (perfil):

```
remaining(A, T, now) = max(0, A * (1 - elapsed_hours / D))
IOB_total = sum(remaining) sobre doses com elapsed < D
```

- Usar `applied_insulin` (não a recomendada).
- Ignorar entries com `applied_insulin` nulo ou ≤ 0.
- Default `D = 4` horas se o usuário ainda não configurou.

### Arredondamento

- Exibir IOB com 1 casa decimal.
- Na recomendação: `dose_bruta = correcao + bolus_comida`; `dose_final = max(0, round_to_step(dose_bruta - IOB))`.

### UX de aviso

Se `IOB > 0`:

- Banner na Home: *“Você ainda tem ~X,X U ativas. A recomendação já desconta isso.”*
- Se `IOB >= dose_bruta`: recomendar `0` e observação clara.

---

## 3. Mudanças de dados (Supabase)

### Migration `002_r0_iob.sql`

```sql
-- Perfil: duração da insulina rápida (horas)
alter table public.profiles
  add column if not exists insulin_duration_hours numeric not null default 4
  check (insulin_duration_hours > 0 and insulin_duration_hours <= 8);

-- Aceite de disclaimer
alter table public.profiles
  add column if not exists disclaimer_accepted_at timestamptz;

-- Entries: permitir soft-delete opcional (ou delete físico via RLS já existente)
-- Política de update já existe; garantir delete (já em 001_init).
```

### Campos Flutter

| Arquivo | Campo |
|---------|--------|
| [`lib/models/profile.dart`](../../lib/models/profile.dart) | `insulinDurationHours`, `disclaimerAcceptedAt` |
| [`lib/models/entry.dart`](../../lib/models/entry.dart) | sem mudança estrutural; IOB calculado em serviço |

---

## 4. Camada de domínio (app)

### Novo: `lib/services/iob_service.dart`

```dart
class IobSnapshot {
  final double iobU;
  final List<IobContribution> contributions; // dose, when, remaining
}

IobSnapshot computeIob({
  required List<Entry> recentEntries,
  required double durationHours,
  required DateTime now,
});
```

- Buscar entries das últimas `durationHours` (query `.gte('recorded_at', ...)`).
- Testes unitários em `test/iob_service_test.dart` (casos: 0 doses, meia vida linear, expirada, múltiplas).

### Atualizar Edge Function / fluxo de cálculo

**Opção escolhida (R0):** app calcula IOB e envia `iob_u` no body; Edge inclui no prompt e na fórmula pedida ao GPT:

```
- IOB atual: {iob_u} U (já subtrair da dose final; nunca recomendar negativo)
```

Resposta JSON passa a incluir:

```json
{
  "carboidratos_g": ...,
  "correcao_u": ...,
  "bolus_comida_u": ...,
  "iob_u": ...,
  "insulina_recomendada_u": ...,
  "observacao": "..."
}
```

Arquivos: [`insulin_service.dart`](../../lib/services/insulin_service.dart), [`recommend-insulin/index.ts`](../../supabase/functions/recommend-insulin/index.ts), [`entry.dart`](../../lib/models/entry.dart) (`InsulinRecommendation`).

---

## 5. UI / fluxos

### 5.1 Perfil

- Campo **Duração da insulina rápida (horas)** — slider ou dropdown: 3 / 3.5 / 4 / 4.5 / 5 (default 4).
- Texto de ajuda: *“Quanto tempo a insulina rápida costuma agir no seu corpo (orientação do seu médico).”*

### 5.2 Home (Dose)

- Ao abrir / antes de calcular: carregar IOB e mostrar banner se `iob > 0`.
- Card de resultado: chip **IOB** além de Carbs / Correção / Comida.
- Passar `iob_u` na chamada `recommend`.

### 5.3 Histórico

- Swipe ou menu (⋮) por card: **Editar** / **Excluir**.
- Editar: bottom sheet ou tela com glicose, alimento, aplicada, data/hora.
- Excluir: confirmação *“Remover este registro?”* → `entries.delete`.
- Após delete/edit: recalcular lista (e IOB na home na próxima visita).

### 5.4 Disclaimer (primeira vez)

- Após perfil completo, se `disclaimer_accepted_at == null`: tela/modal bloqueante.
- Texto curto + checkbox + botão **Concordo e continuar**.
- Persistência: upsert `disclaimer_accepted_at = now()`.
- Gate em [`app.dart`](../../lib/app.dart) `ProfileGate` (ou wrapper após MainShell).

---

## 6. Tickets (backlog R0)

Ordem sugerida de execução:

| ID | Título | Tipo | Aceite |
|----|--------|------|--------|
| **R0-01** | Migration `insulin_duration_hours` + `disclaimer_accepted_at` | DB | Colunas existem; default 4; RLS inalterado |
| **R0-02** | Model/Profile + tela Perfil com duração | App | Usuário salva 3–5h; valor volta no fetch |
| **R0-03** | `IobService` + testes unitários | App | 4+ casos de teste verdes |
| **R0-04** | EntryService: listar por janela de tempo; update + delete | App | update/delete respeitam RLS do user |
| **R0-05** | Home: banner IOB + envio `iob_u` no recommend | App | Banner aparece com IOB>0; request inclui campo |
| **R0-06** | Edge Function: prompt + JSON com IOB | Backend | Deploy; dose final desconta IOB |
| **R0-07** | Histórico: editar entry | App | Altera glicose/aplicada e reflete na lista |
| **R0-08** | Histórico: excluir entry com confirmação | App | Some da lista; storage da foto pode permanecer (ok R0) |
| **R0-09** | Tela/modal de disclaimer + gate | App | Bloqueia uso até aceite; timestamp salvo |
| **R0-10** | QA manual + README R0 | Docs | Checklist abaixo ok |

### Fora do escopo R0 (não criar ticket agora)

- Cálculo 100% local sem GPT (R1)
- Carbs manuais fallback (R1)
- Apagar foto no Storage ao excluir entry (pode ser quick win depois)
- Gráficos, notificações, Health Connect

---

## 7. Checklist de QA (R0-10)

- [ ] Perfil novo: duração default 4h
- [ ] Salvar dose 4 U → imediatamente IOB ≈ 4 U na Home
- [ ] Após ~2h (ou mock de relógio em teste), IOB ≈ 2 U com D=4
- [ ] Calcular com IOB>0 → recomendação menor que sem IOB
- [ ] Editar applied_insulin no histórico → IOB muda
- [ ] Excluir entry → some da lista
- [ ] Disclaimer aparece 1×; depois não reaparece
- [ ] Sem rede / Edge erro: mensagem legível (sem regressão grave)

---

## 8. Riscos e mitigações

| Risco | Mitigação |
|-------|-----------|
| Modelo linear ≠ fisiologia real | Disclaimer + texto “estimativa”; duração editável pelo usuário/médico |
| GPT ignora IOB no prompt | Validar no Edge: se `insulina_recomendada_u > dose_bruta - iob + epsilon`, clampar no servidor |
| Usuário marca applied errado | Edição fácil no histórico (R0-07) |
| Disclaimer legal frágil | Texto claro “não é dispositivo médico”; não substitui advocacia formal |

### Clamp servidor (obrigatório em R0-06)

```ts
const doseBruta = correcao + bolusComida
const clamped = Math.max(0, roundToStep(doseBruta - iob, doseStep))
// usar clamped como insulina_recomendada_u final
```

Assim a segurança não depende só do LLM.

---

## 9. Sequência pós-R0 (teaser R1)

Quando R0 estiver em produção:

1. Edge/app: GPT (ou manual) → só `carboidratos_g`
2. App calcula `correcao`, `bolus_comida`, `− IOB`, `round`
3. Modo offline de carbs manuais

Spec R1 será aberto em `docs/releases/R1-hybrid-spec.md` após fechamento de R0.

---

## 10. Definição de pronto (DoD da release)

- Todos os tickets R0-01…R0-10 feitos ou explicitamente cortados.
- Migration aplicada no projeto Supabase de staging/prod.
- Edge Function redeployada com secret OpenAI.
- `flutter analyze` limpo; testes de IOB passando.
- QA checklist assinado.
