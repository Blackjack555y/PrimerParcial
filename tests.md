# Tests — `parcial/backend/test/`

5 archivos de test con **17 tests y 72 aserciones en total**. Correr cada uno con `ruby -Ilib test/test_X.rb` desde `parcial/backend/`.

## `test_core.rb` (4 tests)

Mecánica básica del modelo (`State` / `TransitionModel`), sobre el escenario real `scenario.json`.

1. **`test_initial_state_matches_scenario`** — el estado inicial arranca en `Z1`, batería 55, `KEY1` en el piso de `Z1`, 2 `FUSE` en `Z2`, nada cargado.
2. **`test_states_are_canonical`** — dos `State` construidos con el mismo contenido pero en distinto orden (`KEY1, CHIP` vs `CHIP, KEY1`) deben ser `==` y tener el mismo `hash`.
3. **`test_closed_door_blocks_move_until_key_is_carried_and_door_opened`** — no se puede mover a `Z2` con `DOOR1` cerrada. La secuencia `PICKUP KEY1 -> OPEN_DOOR -> MOVE` sí lo permite, y la batería baja correctamente (`55-1-2-4=48`).
4. **`test_drop_and_recharge_change_the_expected_state_only`** — `DROP` mueve el objeto de `carried` a `floor` sin mutar el estado original; `RECHARGE` lleva la batería a `battery_max`. Usa `KEY1` con `DOOR1` ya abierta (objeto muerto), porque la política de drop por defecto (`dead_only`) nunca ofrece un objeto vivo como candidato.

## `test_solver_smoke.rb` (6 tests)

Corre `UcsSolver` completo (no solo el modelo) sobre escenarios sintéticos diminutos armados a mano, e imprime el plan encontrado.

1. **`test_goal_already_satisfied_costs_zero`** — si la meta ya está cumplida al inicio, el plan es vacío y costo 0.
2. **`test_single_move_reaches_goal`** — un `MOVE` + `ACTIVATE` alcanza la meta con el costo esperado.
3. **`test_door_and_key_are_required_before_move`** — necesita `PICKUP -> OPEN_DOOR -> MOVE -> ACTIVATE`, en ese orden.
4. **`test_impossible_mission_returns_failure_without_hanging`** — un panel que pide un material/herramienta inexistente hace la misión imposible; el solver termina rápido con `solution_found: false` y `steps: []`.
5. **`test_solve_retries_with_needed_here_when_dead_only_is_genuinely_exhausted`** — si la política de drop por defecto (`dead_only`) agota su espacio de estados sin encontrar meta, `UcsSolver#solve` reintenta automáticamente con la política `needed_here` antes de declarar `FAILURE`. Probado forzando (`define_singleton_method`) la salida del método privado `run`, no con un escenario natural — ver `design.md` §7.1 sobre por qué construir un escenario que realmente rompa `dead_only` resultó sorprendentemente difícil.
6. **`test_solve_does_not_retry_when_dead_only_only_hit_the_expansion_limit`** — si `dead_only` no converge por falta de presupuesto (no por agotar genuinamente el espacio), el solver NO reintenta con `needed_here` — evita duplicar trabajo cuando el reintento probablemente tampoco alcanzaría.

## `test_solver_scenario.rb` (1 test)

El primer test que resuelve `scenario.json` completo de punta a punta (no un escenario sintético). `test_solves_real_scenario_with_dead_only_drop_policy` corre `UcsSolver` con límite de 50.000 expansiones y confirma: `solution_found: true`, costo total **88**, **33 pasos**, `total_cost` igual a la suma de los costos de cada paso, las tres estaciones (`GENERATOR`, `COMMAND`, `ARTILLERY`) activadas.

## `test_search_properties.rb` (5 tests)

Las 5 propiedades de validación exigidas por el enunciado (ENTREGABLE 3), cada una en su propio escenario sintético mínimo:

1. **Estados equivalentes** — recoger `K1` antes que `K2` o al revés da el mismo `State` (`==`, `hash`, `canonical_key`).
2. **Información relevante** — variar batería/posición/carga/puertas/paneles/estaciones por separado siempre da estados distintos; una puerta abierta habilita un `MOVE` antes bloqueado.
3. **Costos diferentes** — una ruta directa de 1 acción (costo 50) pierde contra una ruta de 2 acciones más barata (costo 2): UCS elige la barata aunque tenga más pasos.
4. **Sin solución** — un panel que pide una herramienta/material inexistente termina en `solution_found: false`, `steps: []`, sin colgarse.
5. **Rutas alternativas** — mismo número de acciones, distinto costo: UCS se queda con la ruta barata.

## `test_search_diagnostic.rb` (1 test)

No resuelve nada — explora el escenario real `scenario.json` con un tope duro de **2.000 expansiones** (BFS acotado, no UCS por costo) y reporta métricas (`expanded`, `generated`, `unique`, `max_frontier`, conteo de acciones por tipo). Es la herramienta de diagnóstico usada durante el desarrollo para medir el impacto de cada poda antes de aplicarla — ver `parcial/CONTINUACION.md` y `design.md` §16 (metodología de validación empírica).
