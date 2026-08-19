# Emergency Control — Agente UCS (PrimerParcial)

Agente racional que resuelve el problema "Emergency Control": un robot debe restaurar tres estaciones (`GENERATOR`, `COMMAND`, `ARTILLERY`) en una instalación de cinco zonas, moviéndose por corredores, abriendo puertas con llaves, recogiendo herramientas y materiales, reparando paneles y gestionando batería y capacidad de carga. La estrategia de búsqueda es **Uniform Cost Search (UCS)**.

La implementación entregada vive en [`parcial/`](parcial/) (backend en Ruby, frontend propio). `project/` es el scaffold original de la cátedra (Python/FastAPI + React/TypeScript); no se usó para la entrega — se conserva sin modificar como referencia del contrato y el escenario original.

El diseño formal del agente está documentado en [`design.md`](design.md); el historial de trabajo y las decisiones tomadas durante el desarrollo están en [`parcial/CONTINUACION.md`](parcial/CONTINUACION.md).

---

## 1. Requisitos e instalación de dependencias

- **Ruby 3.x.** Verificar con:
  ```powershell
  ruby --version
  ```
- **Ninguna dependencia externa.** El backend usa únicamente la librería estándar de Ruby (`Socket`, `JSON`) — no hace falta `bundle install`, `gem install` ni ningún gestor de paquetes. Esto fue una decisión deliberada: instalar gems en la máquina de desarrollo falló por interceptación SSL de un antivirus, así que el servidor se escribió sin depender de instalar nada.
- **Un navegador moderno** para ver el frontend (Chrome, Firefox, Edge).

No hay ningún otro paso de instalación.

---

## 2. Iniciar el backend

```powershell
cd parcial/backend
ruby server.rb 3000
```

Esto levanta un servidor HTTP en `http://localhost:3000` que expone la API (sección 4) y además sirve el frontend como archivos estáticos.

Para detenerlo: `Ctrl+C` en la terminal donde corre.

---

## 3. Iniciar el frontend

El frontend **no requiere un paso separado** — el mismo servidor de la sección 2 lo sirve desde el mismo origen. Con el backend corriendo, abrir en el navegador:

```text
http://localhost:3000/
```

Se ve el grafo de las cinco zonas de la instalación con un panel de reproducción del plan al costado.

---

## 4. Ejecutar el agente / 5. Probar una misión

Hay tres formas, de más visual a más directa:

### a) Desde el navegador (recomendado para revisar visualmente)

Con `http://localhost:3000/` abierto:

1. Click en **Resolver**. Llama a `POST /api/solve` con el escenario por defecto y carga el plan encontrado.
2. Click en **▶ (Reproducir)** para ver al robot moverse por el mapa, las puertas abrirse, las estaciones encenderse y la batería/costo actualizarse paso a paso. También se puede avanzar/retroceder manualmente o saltar a cualquier paso haciendo click en el log.
3. Al final de la página aparece la **bitácora de la misión**: una tabla con los 33 pasos del plan, cada uno con su descripción en lenguaje natural, costo, costo acumulado, batería restante y carga transportada en ese momento.

### b) Por línea de comandos (`curl`), contra el escenario por defecto

```bash
curl -X POST http://localhost:3000/api/solve -H "Content-Type: application/json" --data-binary ""
```

Un body vacío hace que el servidor use `parcial/backend/scenarios/scenario.json`.

### c) Por línea de comandos, contra un escenario propio

`POST /api/solve` acepta cualquier escenario con la misma forma (no está hardcodeado a la instancia de ejemplo — el agente fue diseñado y probado para generalizar, ver `design.md` sección 5 y `CONTRATO.md`):

```bash
curl -X POST http://localhost:3000/api/solve -H "Content-Type: application/json" -d '{
  "robot": {"start":"A","battery_max":20,"battery_start":20,"cargo_capacity":3},
  "zones": [{"id":"A"},{"id":"B"}],
  "corridors": [{"from":"A","to":"B","cost":4,"door":null}],
  "stations": [{"id":"S","zone":"B","state":"OFFLINE","requires":{}}],
  "goal": {"stations_online":["S"]}
}'
```

También se puede consultar el escenario por defecto sin resolverlo: `GET http://localhost:3000/api/scenario`.

---

## 6. Interpretar el resultado

`POST /api/solve` devuelve siempre este formato (fijado por `CONTRATO.md`):

```json
{
  "solution_found": true,
  "total_cost": 88,
  "steps": [
    { "op": "MOVE", "from": "Z1", "to": "Z2", "cost": 4 },
    { "op": "PICKUP", "item": "KEY1", "cost": 1 },
    { "op": "INTERACT", "target": "DOOR1", "action": "OPEN_DOOR", "cost": 2 },
    { "op": "INTERACT", "target": "PANEL_A", "action": "REPAIR", "consumes": "FUSE", "cost": 2 }
  ],
  "message": "Solution found after 35786 expansions"
}
```

- **`solution_found`**: si el agente encontró un plan que cumple la misión (todas las estaciones de `goal.stations_online` quedan `ONLINE`).
- **`total_cost`**: suma de los costos de todos los pasos — es el criterio que UCS minimiza (no la cantidad de pasos).
- **`steps`**: el plan, usando únicamente las cuatro operaciones del contrato: `MOVE` (mover entre zonas), `PICKUP`/`DROP` (recoger/dejar un objeto), `INTERACT` (con `action` igual a `OPEN_DOOR`, `REPAIR`, `ACTIVATE` o `RECHARGE`).
- **`message`**: texto informativo (cuántas expansiones tomó, o por qué falló).

**Caso sin solución (`FAILURE`):** cuando la misión no se puede completar, la respuesta es:

```json
{ "solution_found": false, "total_cost": 0, "steps": [], "message": "No solution found after 1 expansions" }
```

El agente siempre termina — nunca se queda explorando indefinidamente (límite explícito de expansiones, ver `design.md` sección 12).

---

## Tests

```powershell
cd parcial/backend
ruby -Ilib test/test_core.rb              # mecanica basica del estado (State/TransitionModel)
ruby -Ilib test/test_solver_smoke.rb       # UcsSolver completo sobre escenarios sinteticos chicos
ruby -Ilib test/test_solver_scenario.rb    # UcsSolver resuelve scenario.json de punta a punta (costo 88)
ruby -Ilib test/test_search_properties.rb  # las 5 propiedades de validacion exigidas por el enunciado
ruby -Ilib test/test_search_diagnostic.rb  # diagnostico acotado de exploracion (no resuelve, solo mide)
```

`test_search_properties.rb` cubre, cada uno en su propio escenario mínimo:

1. **Estados equivalentes** — historias distintas que llegan a la misma configuración producen el mismo `State`.
2. **Información relevante** — cambiar batería/posición/carga/puertas/paneles/estaciones produce estados distintos.
3. **Costos diferentes** — una ruta con menos acciones pierde contra una con más acciones pero menor costo.
4. **Sin solución** — termina en `FAILURE` sin colgarse.
5. **Rutas alternativas** — entre dos rutas con igual cantidad de acciones, UCS se queda con la de menor costo.

---

## Estructura del proyecto

```text
parcial/
├── backend/
│   ├── lib/            # Scenario, State, TransitionModel, SuccessorGenerator, UcsSolver, PlanFormatter
│   ├── test/
│   ├── scenarios/scenario.json
│   └── server.rb       # HTTP sin gems (TCPServer de la libreria estandar)
├── frontend/            # Grafo + reproduccion del plan + bitacora, HTML/CSS/JS sin build step
└── CONTINUACION.md       # historial de trabajo y decisiones de diseno
```
