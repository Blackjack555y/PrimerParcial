# ParcialRuby - Emergency Facility Control Agent

AI agent solver implementation in Ruby for the PrimerParcial university project.

## Structure

```
parcial/
├── Gemfile              # Dependencies
├── Gemfile.lock         # Lock file
├── config/
│   ├── routes.rb
│   ├── database.yml
│   └── puma.rb
├── backend/
│   ├── controllers/
│   │   ├── api/
│   │   │   └── solve_controller.rb
│   │   └── pages_controller.rb
│   ├── models/
│   │   ├── state.rb
│   │   ├── facility.rb
│   │   └── solver.rb
│   ├── services/
│   │   ├── ucs_solver.rb
│   │   ├── state_manager.rb
│   │   └── plan_executor.rb
│   ├── views/
│   │   ├── pages/
│   │   │   └── index.html.erb
│   │   └── layouts/
│   └── assets/
│       ├── stylesheets/
│       └── javascripts/
├── lib/
│   └── agents/
│       ├── graph_search.rb
│       └── state_representation.rb
├── spec/
│   ├── services/
│   ├── models/
│   └── scenarios/
├── db/
│   └── schema.rb
└── README.md
```

## Setup

```bash
cd parcial
bundle install
rails db:create
rails s -p 3000
```

## API Endpoints

### POST /api/solve
Solves the emergency facility control problem.

**Request:**
```json
{
  "zones": [...],
  "corridors": [...],
  "doors": [...],
  "keys": [...],
  "materials": [...],
  "tools": [...],
  "stations": [...],
  "panels": [...],
  "robot": {...}
}
```

**Response:**
```json
{
  "solution_found": true,
  "total_cost": 63,
  "steps": [
    { "op": "MOVE", "from": "Z1", "to": "Z2", "cost": 4 }
  ]
}
```

## Key Classes

- **State**: Represents facility state (robot position, battery, inventory, world state)
- **UCSolver**: Uniform Cost Search implementation
- **StateMangaer**: State transitions and validation
- **PlanExecutor**: Converts internal actions to CONTRATO-compliant operations

## Testing

```bash
bundle exec rspec spec/
```
