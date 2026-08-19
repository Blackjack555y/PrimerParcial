require_relative 'test_helper'

# Sanity checks that UcsSolver actually works on tiny, hand-built scenarios
# before trusting it on the full scenario.json (see CONTINUACION.md sec. 7 paso 6).
class SolverSmokeTest < Minitest::Test
  def base_robot(start: 'A', battery: 20)
    { 'start' => start, 'battery_max' => 20, 'battery_start' => battery, 'cargo_capacity' => 3 }
  end

  def describe_plan(result)
    if result[:solution_found]
      plan = result[:steps].map { |step| step['action'] ? "#{step['op']}:#{step['action']}" : step['op'] }.join(' -> ')
      plan = '(sin pasos, meta ya cumplida)' if plan.empty?
      puts "  RESULT solution_found=true total_cost=#{result[:total_cost]} plan=[#{plan}]"
    else
      puts "  RESULT solution_found=false message=#{result[:message].inspect}"
    end
  end

  def test_goal_already_satisfied_costs_zero
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }],
      'corridors' => [],
      'stations' => [{ 'id' => 'S', 'zone' => 'A', 'state' => 'ONLINE', 'requires' => {} }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario).solve
    describe_plan(result)

    assert result[:solution_found]
    assert_equal 0, result[:total_cost]
    assert_empty result[:steps]
  end

  def test_single_move_reaches_goal
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'B' }],
      'corridors' => [{ 'from' => 'A', 'to' => 'B', 'cost' => 4, 'door' => nil }],
      'stations' => [{ 'id' => 'S', 'zone' => 'B', 'state' => 'OFFLINE', 'requires' => {} }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario).solve
    describe_plan(result)

    assert result[:solution_found]
    assert_equal 4 + 2, result[:total_cost] # MOVE(4) + INTERACT/ACTIVATE(2)
    assert_equal %w[MOVE INTERACT], result[:steps].map { |step| step['op'] }
  end

  def test_door_and_key_are_required_before_move
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'B' }],
      'corridors' => [{ 'from' => 'A', 'to' => 'B', 'cost' => 1, 'door' => 'DOOR1' }],
      'doors' => [{ 'id' => 'DOOR1', 'key' => 'KEY1', 'state' => 'CLOSED', 'between' => %w[A B] }],
      'keys' => [{ 'id' => 'KEY1', 'zone' => 'A', 'weight' => 1 }],
      'stations' => [{ 'id' => 'S', 'zone' => 'B', 'state' => 'OFFLINE', 'requires' => {} }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario).solve
    describe_plan(result)

    assert result[:solution_found]
    assert_equal %w[PICKUP INTERACT MOVE INTERACT], result[:steps].map { |step| step['op'] }
    assert_equal 'OPEN_DOOR', result[:steps][1]['action']
  end

  def test_impossible_mission_returns_failure_without_hanging
    scenario = Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }],
      'corridors' => [],
      'panels' => [{ 'id' => 'P', 'zone' => 'A', 'requires' => { 'tool' => 'MISSING_TOOL', 'material' => 'MISSING_MAT' }, 'state' => 'DAMAGED' }],
      'stations' => [{ 'id' => 'S', 'zone' => 'A', 'state' => 'OFFLINE', 'requires' => { 'panels_ok' => ['P'] } }],
      'goal' => { 'stations_online' => ['S'] }
    )

    result = UcsSolver.new(scenario).solve
    describe_plan(result)

    refute result[:solution_found]
    assert_equal [], result[:steps]
    assert_equal 0, result[:total_cost]
  end

  # dead_only is fast but not proven complete in general (see design.md 7.1
  # and CONTINUACION.md): an instance could genuinely require dropping a
  # still-useful item, which dead_only never offers. Constructing a natural
  # scenario that actually defeats dead_only turned out to be surprisingly
  # hard -- this world's monotonicity (doors/panels/stations never revert)
  # lets almost any capacity crunch be solved by fetching one tool+material
  # pair at a time. That is itself informative, not a proof of completeness,
  # so the fallback stays as a safety net and is tested directly here by
  # forcing the primary attempt to genuinely exhaust its search space.
  def trivial_scenario
    Scenario.new(
      'robot' => base_robot,
      'zones' => [{ 'id' => 'A' }, { 'id' => 'B' }],
      'corridors' => [{ 'from' => 'A', 'to' => 'B', 'cost' => 4, 'door' => nil }],
      'stations' => [{ 'id' => 'S', 'zone' => 'B', 'state' => 'OFFLINE', 'requires' => {} }],
      'goal' => { 'stations_online' => ['S'] }
    )
  end

  def test_solve_retries_with_needed_here_when_dead_only_is_genuinely_exhausted
    solver = UcsSolver.new(trivial_scenario)
    calls = []
    fallback_result = { solution_found: true, total_cost: 4, steps: [{ 'op' => 'MOVE' }], message: 'Solution found after 3 expansions' }
    solver.define_singleton_method(:run) do |policy|
      calls << policy
      policy == :dead_only ? { solution_found: false, total_cost: 0, steps: [], message: 'No solution found after 5 expansions' } : fallback_result
    end

    result = solver.solve

    assert_equal %i[dead_only needed_here], calls
    assert result[:solution_found]
    assert_equal 4, result[:total_cost]
    assert_includes result[:message], 'dead_only found no plan; retried with needed_here'
  end

  def test_solve_does_not_retry_when_dead_only_only_hit_the_expansion_limit
    solver = UcsSolver.new(trivial_scenario)
    calls = []
    solver.define_singleton_method(:run) do |policy|
      calls << policy
      { solution_found: false, total_cost: 0, steps: [], message: 'Search limit reached after 5 expansions' }
    end

    result = solver.solve

    assert_equal %i[dead_only], calls
    refute result[:solution_found]
  end
end
