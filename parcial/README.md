# ParcialRuby - Emergency Facility Control Agent

Agente UCS (Uniform Cost Search) en Ruby para el problema "Emergency Control" del PrimerParcial. Ver `design.md` (raíz del repo) para el diseño formal y `CONTINUACION.md` para el historial de trabajo.

## Estructura

```
parcial/
├── lib/
│   ├── scenario.rb           # Carga y valida el escenario JSON
│   ├── state.rb               # Estado físico canónico e inmutable
│   ├── item_liveness.rb       # ¿Puede este objeto seguir habilitando una accion futura?
│   ├── transition_model.rb    # Aplica una accion y produce el estado sucesor
│   ├── successor_generator.rb # Applicable(state)
│   ├── ucs_solver.rb          # Uniform Cost Search + dominancia
│   └── plan_formatter.rb      # Traduce a la salida fija del contrato
├── test/                      # ruby -Ilib test/test_X.rb
├── scenarios/scenario.json    # Escenario de referencia
├── server.rb                  # Servidor HTTP (sin gems, solo Ruby core)
└── frontend/grafo/            # Visualizacion estatica del grafo
```

Ningún archivo de `lib/` conoce HTTP; el servidor es un envoltorio delgado.

## Correr el servidor

No requiere `bundle install` ni gems externas — usa `TCPServer` de la librería estándar.

```powershell
cd parcial
ruby server.rb 3000
```

## API

### `GET /api/health`

`{ "status": "ok" }`

### `GET /api/scenario`

Devuelve `scenarios/scenario.json` tal cual.

### `POST /api/solve`

Resuelve el escenario recibido en el body. Si el body está vacío, usa `scenarios/scenario.json` por defecto.

**Request:** el JSON completo del escenario (`zones`, `corridors`, `robot`, `doors`, `keys`, `tools`, `materials`, `panels`, `stations`, `chargers`, `goal`, `action_costs`).

**Response** (formato fijo, ver `CONTRATO.md` en la raíz):
```json
{
  "solution_found": true,
  "total_cost": 88,
  "steps": [
    { "op": "MOVE", "from": "Z1", "to": "Z2", "cost": 4 }
  ],
  "message": "Solution found after 35786 expansions"
}
```

## Tests

```powershell
cd parcial
ruby -Ilib test/test_core.rb
ruby -Ilib test/test_solver_smoke.rb
ruby -Ilib test/test_solver_scenario.rb
ruby -Ilib test/test_search_properties.rb
ruby -Ilib test/test_search_diagnostic.rb
```
