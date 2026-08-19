# Tests — `parcial/test/`

Tenemos 3 archivos de test con **9 tests en total**.

## `test_core.rb`

Mecánica básica del modelo (`State` / `TransitionModel`), sobre el escenario real `scenario.json`.

1. **`test_initial_state_matches_scenario`**
   El estado inicial arranca en `Z1`, batería 55, `KEY1` en el piso de `Z1`, 2 `FUSE` en `Z2`, nada cargado.

2. **`test_states_are_canonical`**
   Dos `State` construidos con el mismo contenido pero en distinto orden (`KEY1, CHIP` vs `CHIP, KEY1`) deben ser `==` y tener el mismo `hash`. Prueba la canonicalización.

3. **`test_closed_door_blocks_move_until_key_is_carried_and_door_opened`**
   No se puede mover a `Z2` con `DOOR1` cerrada. La secuencia `PICKUP KEY1 -> OPEN_DOOR -> MOVE` sí lo permite, y la batería baja correctamente (`55-1-2-4=48`).

4. **`test_drop_and_recharge_change_the_expected_state_only`**
   `DROP` mueve el objeto de `carried` a `floor` sin mutar el estado original (inmutabilidad); `RECHARGE` lleva la batería a `battery_max`.

## `test_solver_smoke.rb`

Corre `UcsSolver` completo (no solo el modelo) sobre escenarios sintéticos diminutos armados a mano, y ahora imprime el plan encontrado.

1. **`test_goal_already_satisfied_costs_zero`**
   Si la meta ya está cumplida al inicio, el plan es vacío y costo 0.

2. **`test_single_move_reaches_goal`**
   Un `MOVE` + `ACTIVATE` alcanza la meta con el costo esperado.

3. **`test_door_and_key_are_required_before_move`**
   Necesita `PICKUP -> OPEN_DOOR -> MOVE -> ACTIVATE`, en ese orden.

4. **`test_impossible_mission_returns_failure_without_hanging`**
   Un panel que pide un material/herramienta inexistente hace la misión imposible; el solver debe terminar rápido con `solution_found: false` y `steps: []`, sin colgarse.

## `test_search_diagnostic.rb`

No resuelve nada, solo explora el escenario real `scenario.json` con un tope duro de **2.000 expansiones** (BFS acotado, no UCS) y reporta métricas (`expanded`, `generated`, `unique`, `max_frontier`, conteo de acciones por tipo).

Es la herramienta de diagnóstico que usamos para medir si la poda de objetos muertos realmente reduce la explosión de estados — que sería justamente el **"paso 3"** pendiente.