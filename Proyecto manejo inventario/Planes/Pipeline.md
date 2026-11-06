# Pipeline — modelos por rol y costo estimado

> **Decisión de modelos para el pipeline SDD.** Precios verificados en vivo contra
> la API de OpenRouter el 06/11/2026.
> Relacionado: [[Auditoria Opus - 03-11-2026]], [[PENDIENTES]], [[Realizar en casa]]
> Config: `.opencode/opencode.json`
> Estado: **propuesto, aún no aplicado** — el archivo sigue en la configuración actual (Opus/Sonnet/Pro).

**Principio:** manos baratas donde la spec ya hizo el razonamiento; QA barato porque
verificar es lectura; cerebro caro donde un error de criterio no se ve.

---

## Precios en vivo (06/11/2026, USD por 1M tokens)

| Modelo | In | Out | Cache read | Contexto | Tools |
|---|---|---|---|---|---|
| `anthropic/claude-opus-5.5` | 4,00 | 20,00 | 0,20 | 1M | ✅ |
| `anthropic/claude-sonnet-5.5` | 2,00 | 10,00 | 0,10 | 1M | ✅ |
| `deepseek/deepseek-v4-pro-0813` | 0,1165 | **4,66** | 0,111 | 1M | ✅ |
| `deepseek/deepseek-v4-flash` | 0,091 | **0,182** | 0,0182 | 1M | ✅ |
| `anthropic/claude-haiku-5.5` | 0,10 | 0,50 | 0,01 | 1M | ✅ |

---

## Asignación por rol

| Rol | Clave en config | Modelo |
|---|---|---|
| Cerebro — orquestador | `gentle-orchestrator` | **Opus 5.5** o **Sonnet 5.5** (ver Opciones) |
| Cerebro — diseño de spec | `sdd-design` | igual que el orquestador (ver Punto medio) |
| Manos — implementación | `sdd-apply` | `deepseek-v4-flash` |
| Manos — exploración | `explore`, `general` | `deepseek-v4-flash` |
| Manos — fix | `jd-fix-agent` | `deepseek-v4-flash` |
| QA — verificación | `sdd-verify` | `claude-haiku-5.5` |
| QA — review nativo | `review-risk`, `review-resilience`, `review-readability`, `review-reliability` | `claude-haiku-5.5` |
| QA — refuter / validator | `review-refuter`, `review-validator` | `claude-haiku-5.5` |
| QA — judgment day | `jd-judge-a`, `jd-judge-b` | `claude-haiku-5.5` |

---

## Las dos opciones

| Clave | Opción A — $87 | Opción B — $44 |
|---|---|---|
| `gentle-orchestrator.model` | `claude-opus-5.5` | `claude-sonnet-5.5` |
| `sdd-design.model` | `claude-opus-5.5` | `claude-sonnet-5.5` |
| resto (manos + QA) | Flash + Haiku | Flash + Haiku |

**La diferencia entre A y B son exactamente dos claves.** Todo lo demás es idéntico:
el código escrito (Flash) y la verificación (Haiku) son los mismos modelos en ambas.

---

## Qué cambia de verdad entre A y B

**El diseño de la spec.** `sdd-design` escribe el documento que leen todos los demás.
Un requisito mal entendido ahí se propaga a 45 ciclos. Opus cuesta 2× más en output
porque piensa más antes de escribir.

**Las decisiones del orquestador.** Decide qué delegar, cuándo parar, si un diff cumple
la spec, y escribe inline en tareas chicas. Opus falla menos en routing; Sonnet a veces
toma el atajo — delega cuando debió escribir, o aprueba algo que no cerraba.

**El modo de falla.** Con Opus los errores que quedan son de detalle. Con Sonnet son de
criterio: algo que *parece* terminado y no lo es. **Y ese error `sdd-verify` con Haiku no
lo agarra** — verifica contra la spec, y si la spec o el routing estuvo mal, verifica bien
algo mal planteado.

**Lo que NO cambia:** el código escrito, la verificación, el volumen de tokens, los
límites de contexto (ambos 1M).

---

## Desglose del estimado

| Componente | Opción A (Opus) | Opción B (Sonnet) |
|---|---|---|
| Orquestador, ~600 turns | 71,58 | 35,79 |
| Design, ~45 specs | 13,68 | 6,84 |
| Apply (Flash) | 0,61 | 0,61 |
| QA (Haiku) | 1,20 | 1,20 |
| **Total** | **≈ 87** | **≈ 44** |

**Supuestos:** 45 ciclos SDD (Fase 1: 1, Fase 2: 4, Fase 3: 40), ~600 turns de
orquestador, 80-85% de input cacheado.

---

## Punto medio recomendado — ≈ $51

**Opus en `sdd-design` + Sonnet en `gentle-orchestrator`**, resto igual:

| Componente | Costo |
|---|---|
| Design (Opus) | 13,68 |
| Orquestador (Sonnet) | 35,79 |
| Apply (Flash) | 0,61 |
| QA (Haiku) | 1,20 |
| **Total** | **≈ 51** |

Son **$7 más que la opción B** y conserva la calidad en el punto de mayor apalancamiento:
la spec. El orquestador falla más barato porque aguas abajo lo atrapan `sdd-verify` y el
review nativo; **la spec no tiene red de esa naturaleza — si falla, todo lo siguiente falla
en cadena.**

**Recomendación:** los $87 de la A solo se justifican si la migración de 8.600 líneas da
ansiedad por errores de criterio. Para la Fase 1 (220 líneas de `clientes`) y la Fase 2
(PoC Qt), los **$51** son el mejor punto. Si en la Fase 3 —`ventas` y `compras`— se ve que
el orquestador aprueba cosas que no cerraban, subir a Opus **solo para esa fase**.

---

## Por qué Flash y no Pro para las manos

La salida de Pro cuesta **25,6×** más que Flash ($4,66 vs $0,182), y la calidad no acompaña:

| Benchmark | Pro 0813 | Flash | Ganador |
|---|---|---|---|
| SWE-bench Verified | 80,6 | 79,0 | Pro +1,6 |
| SWE-bench Pro | 55,4 | 52,6 | Pro +2,8 |
| LiveCodeBench | 93,5 | 91,6 | Pro +1,9 |
| **Terminal-Bench 4.0** (agéntico) | 14,1 | **26,8** | **Flash +12,7** |

Se pagan 25,6× por 1,6-2,8 puntos en coding, y en trabajo agéntico real **Flash le gana
por 12,7 puntos** — el checkpoint `-0731` es un upgrade de post-training posterior.
Fuentes independientes señalan que el trabajo agéntico de shell "era la razón canónica
para escalar de Flash a Pro; ahora es la mejor razón para no hacerlo".

Y el detalle que sella la decisión: `sdd-apply` no piensa solo — recibe una spec escrita
por diseño. **El razonamiento difícil ya está aguas arriba; las manos solo ejecutan.**

---

## QA: Haiku 5.5 en vez de Sonnet

| | Sonnet 5.5 | Haiku 5.5 |
|---|---|---|
| Output por M | 10,00 | 0,50 |
| Contexto | 1M | 1M |
| Costo QA estimado | ≈ 21 | **≈ 1,20** |

Baja **20× en output** sin perder contexto ni tools. Verificar es lectura: comparar un
diff contra una spec y correr comprobaciones no necesita el mismo modelo que escribió el
criterio.

---

## Modelos descartados (verificado 06/11/2026)

| Modelo | Motivo |
|---|---|
| `qwen/qwen-2.5-coder-32b-instruct` | **`tools: false`** en OpenRouter — no puede ser agente. Además **32.768** de contexto, insuficiente para el prompt de sistema. Es modelo de completion, no de orquestación |
| `anthropic/claude-3.5-haiku` | **Retirado por Anthropic el 19/02/2026**; ya ni aparece en el catálogo de OpenRouter (0 resultados) |
| `meta-llama/llama-3.3-70b-instruct` | Funciona (tools ✅, 131K) pero sale **$0,59/$0,79 — más caro que Haiku 5.5 en ambas direcciones** ($0,10/$0,50) con 8× menos contexto. Es de dic-2024, agentic flojo (Berkeley Function Calling 31,9%) |

---

## Por qué la suscripción no aplica

- **OpenRouter gana:** toda la migración ($75-130) cuesta **menos que un mes de Claude
  Max 5x** ($100).
- **La triada es multi-proveedor:** una suscripción de Claude no da DeepSeek — obligaría
  a mover las manos a un modelo 3× más caro, perdiendo el eslabón barato.
- **ToS:** Anthropic prohíbe explícitamente el login de claude.ai en herramientas de
  terceros. OpenCode 2.2.3 lo promete, pero Anthropic no se ha pronunciado.
- **`cost-policy.md` es secuencial** (un subagente a la vez): ese patrón premia el pago
  por token, no el techo fijo de una suscripción.

---

## Palancas de costo, por impacto

1. **Orquestador Opus → Sonnet:** ahorra ~$36 (casi la mitad de la factura).
2. **QA Sonnet → Haiku:** ahorra ~$20.
3. **Manos Pro → Flash:** ahorra apenas ~$7 de $94 — **el rol que menos se nota**.

El 90% del costo es el cerebro. Baratar las manos no mueve el número.

---

## Próximo paso

Aplicar la opción elegida en `.opencode/opencode.json` y medir la tasa de quemado real
con la Fase 1 de `clientes` (~$5), que es el calibrador del resto del estimado.
