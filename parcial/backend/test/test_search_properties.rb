require_relative 'test_helper'

# ENTREGABLE 3 - VALIDACION: las 5 propiedades exigidas para la estrategia de
# busqueda, cada una aislada en un escenario minimo propio (no en scenario.json)
# para que la causa de una falla sea inequivoca.
class SearchPropertiesTest < Minitest::Test
  def base_robot(start: 'A', battery: 100)
    { 'start' => start, 'battery_max' => 100, 'battery_start' => battery, 'cargo_capacity' => 3 }
  end

  # Caso 1: dos historias distintas que llegan a la misma configuracion fisica
  # deben producir el mismo estado logico (==, hash, canonical_key).
  def test_case1_equivalent_configurations_produce_the_same_state
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'B' }, { 'id' => 'C' }],
      'corridors' => [],
      'doors' => [
        { 'id' => 'D1', 'key' => 'K1', 'state' => 'CLOSED', 'between' => %w[A B] },
        { 'id' => 'D2', 'key' => 'K2', 'state' => 'CLOSED', 'between' => %w[A C] }
      ],
      'keys' => [
        { 'id' => 'K1', 'zone' => 'A', 'weight' => 1 },
        { 'id' => 'K2', 'zone' => 'A', 'weight' => 1 }
      ]
    )
    model = TransitionModel.new(scenario)
    generator = SuccessorGenerator.new(scenario)
    initial = State.initial(scenario)

    pick = ->(state, item) { model.apply(state, generator.applicable(state).find { |a| a[:type] == :pickup && a[:item] == item }) }

    k1_then_k2 = pick.call(pick.call(initial, 'K1'), 'K2')
    k2_then_k1 = pick.call(pick.call(initial, 'K2'), 'K1')

    assert_equal k1_then_k2, k2_then_k1
    assert_equal k1_then_k2.hash, k2_then_k1.hash
    liveness = ItemLiveness.new(scenario)
    assert_equal k1_then_k2.canonical_key(liveness), k2_then_k1.canonical_key(liveness)
  end

  # Caso 2: dos configuraciones que difieren en informacion que puede cambiar
  # acciones futuras deben seguir siendo estados distintos.
  def test_case2_relevant_differences_keep_states_distinct
    base = State.new(
      pos: 'A', battery: 50, carried: { 'K1' => 1 }, floor: { 'A' => { 'FUSE' => 1 } },
      doors_open: [], panels_repaired: [], stations_online: []
    )

    variants = {
      battery: base.class.new(pos: 'A', battery: 49, carried: { 'K1' => 1 }, floor: { 'A' => { 'FUSE' => 1 } }, doors_open: [], panels_repaired: [], stations_online: []),
      pos: base.class.new(pos: 'B', battery: 50, carried: { 'K1' => 1 }, floor: { 'A' => { 'FUSE' => 1 } }, doors_open: [], panels_repaired: [], stations_online: []),
      carried: base.class.new(pos: 'A', battery: 50, carried: {}, floor: { 'A' => { 'FUSE' => 1, 'K1' => 1 } }, doors_open: [], panels_repaired: [], stations_online: []),
      doors_open: base.class.new(pos: 'A', battery: 50, carried: { 'K1' => 1 }, floor: { 'A' => { 'FUSE' => 1 } }, doors_open: ['D1'], panels_repaired: [], stations_online: []),
      panels_repaired: base.class.new(pos: 'A', battery: 50, carried: { 'K1' => 1 }, floor: { 'A' => { 'FUSE' => 1 } }, doors_open: [], panels_repaired: ['P1'], stations_online: []),
      stations_online: base.class.new(pos: 'A', battery: 50, carried: { 'K1' => 1 }, floor: { 'A' => { 'FUSE' => 1 } }, doors_open: [], panels_repaired: [], stations_online: ['S1'])
    }

    variants.each do |dimension, variant|
      refute_equal base, variant, "Cambiar #{dimension} deberia producir un estado distinto"
    end

    # Y ese cambio realmente habilita/bloquea acciones: una puerta abierta
    # habilita un MOVE que antes estaba bloqueado.
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'B' }],
      'corridors' => [{ 'from' => 'A', 'to' => 'B', 'cost' => 1, 'door' => 'D1' }],
      'doors' => [{ 'id' => 'D1', 'key' => 'K1', 'state' => 'CLOSED', 'between' => %w[A B] }]
    )
    generator = SuccessorGenerator.new(scenario)
    closed_state = State.new(pos: 'A', battery: 10, carried: {}, floor: {}, doors_open: [], panels_repaired: [], stations_online: [])
    open_state = State.new(pos: 'A', battery: 10, carried: {}, floor: {}, doors_open: ['D1'], panels_repaired: [], stations_online: [])

    refute generator.applicable(closed_state).any? { |a| a[:type] == :move }
    assert generator.applicable(open_state).any? { |a| a[:type] == :move }
  end

  # Caso 3: la ruta con menos acciones no gana automaticamente si cuesta mas.
  def test_case3_fewer_actions_does_not_win_if_it_costs_more
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'B' }, { 'id' => 'C' }],
      'corridors' => [
        { 'from' => 'A', 'to' => 'B', 'cost' => 50, 'door' => nil }, # 1 accion, caro
        { 'from' => 'A', 'to' => 'C', 'cost' => 1, 'door' => nil },  # 2 acciones, barato
        { 'from' => 'C', 'to' => 'B', 'cost' => 1, 'door' => nil }
      ],
      'stations' => [{ 'id' => 'S', 'zone' => 'B', 'state' => 'OFFLINE', 'requires' => {} }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario).solve

    assert result[:solution_found]
    assert_equal 4, result[:total_cost] # 1 + 1 (moves) + 2 (activate), no los 50 + 2 del atajo
    assert_equal %w[MOVE MOVE INTERACT], result[:steps].map { |s| s['op'] }
  end

  # Caso 4: mision imposible termina en FAILURE (solution_found: false,
  # steps: []), sin quedar explorando indefinidamente.
  def test_case4_impossible_mission_returns_failure
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }],
      'corridors' => [],
      'panels' => [{ 'id' => 'P', 'zone' => 'A', 'requires' => { 'tool' => 'GHOST_TOOL', 'material' => 'GHOST_MAT' }, 'state' => 'DAMAGED' }],
      'stations' => [{ 'id' => 'S', 'zone' => 'A', 'state' => 'OFFLINE', 'requires' => { 'panels_ok' => ['P'] } }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario, max_expansions: 1_000).solve

    refute result[:solution_found]
    assert_equal [], result[:steps]
    assert_equal 0, result[:total_cost]
  end

  # Caso 5: dos rutas alternativas con la MISMA cantidad de acciones pero
  # distinto costo -- UCS debe conservar la de menor costo.
  def test_case5_alternative_routes_keep_the_cheapest
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'X' }, { 'id' => 'Y' }, { 'id' => 'B' }],
      'corridors' => [
        { 'from' => 'A', 'to' => 'X', 'cost' => 5, 'door' => nil },
        { 'from' => 'X', 'to' => 'B', 'cost' => 5, 'door' => nil },
        { 'from' => 'A', 'to' => 'Y', 'cost' => 1, 'door' => nil },
        { 'from' => 'Y', 'to' => 'B', 'cost' => 1, 'door' => nil }
      ],
      'stations' => [{ 'id' => 'S', 'zone' => 'B', 'state' => 'OFFLINE', 'requires' => {} }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario).solve

    assert result[:solution_found]
    assert_equal 4, result[:total_cost] # via Y (1+1), no via X (5+5)
    assert_equal 'Y', result[:steps].first['to']
  end
end
