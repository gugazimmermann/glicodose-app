# Decisão de release — App Diabetes

**Data:** 2026-09-16  
**Decisor:** Product (recomendação executiva do roadmap)  
**Status:** Aprovado

## Release escolhida: **R0 — Segurança (IOB)**

### Por quê R0 (e não R1–R4 agora)

1. **Risco clínico imediato:** o MVP pode recomendar nova dose completa enquanto ainda há insulina ativa → overdose.
2. **Pré-requisito de R1:** o cálculo híbrido (fórmula local − IOB) depende de duração da insulina e histórico de doses aplicadas.
3. **Escopo contido:** mudanças em perfil, entries, home e edge function — sem gráficos, notificações ou integrações.
4. Alinha com a recomendação do roadmap: *“O próximo investimento de maior ROI não é mais UI: é IOB…”*.

### Fora desta release

| Release | Motivo de adiar |
|---------|-----------------|
| R1 Cálculo híbrido | Vem logo após R0; especificado como “seguinte” no doc de R0 |
| R2 Dashboard/gráficos | Valor diário, não bloqueia segurança |
| R3 Lembretes/export | Engajamento |
| R4 Health/CGM | Escala |

### Critério de sucesso de R0

- Usuário com dose recente vê **IOB residual** na tela de dose.
- Recomendação **subtrai IOB** (ou avisa e zera correção se IOB alto).
- Usuário consegue **editar e apagar** registros do histórico.
- Aceite de disclaimer na primeira sessão após login com perfil completo.

### Próximo passo

Ver especificação técnica e tickets em [`R0-iob-spec.md`](R0-iob-spec.md).
