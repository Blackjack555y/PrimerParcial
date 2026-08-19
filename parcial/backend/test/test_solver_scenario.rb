require_relative 'test_helper'

# End-to-end: UcsSolver actually solves the real scenario.json, not just the
# tiny hand-built ones in test_solver_smoke.rb. Bounded so a regression fails
# fast instead of hanging (see CONTINUACION.md).
class SolverScenarioTest < Minitest::Test
  MAX_EXPANSIONS = 50_000

  def test_solves_real_scenario_with_dead_only_drop_policy
    scenario = Scenario.from_file(SCENARIO_PATH)
    result = UcsSolver.new(scenario, drop_policy: :dead_only, max_expansions: MAX_EXPANSIONS).solve

    puts "  RESULT solution_found=#{result[:solution_found]} total_cost=#{result[:total_cost]} " \
         "steps=#{result[:steps].length} message=#{result[:message].inspect}"

    assert result[:solution_found], "Expected a solution within #{MAX_EXPANSIONS} expansions"
    assert_equal 88, result[:total_cost]
    assert_equal 33, result[:steps].length

    ops = result[:steps].map { |step| step['op'] }
    assert_equal result[:total_cost], result[:steps].sum { |step| step['cost'] }
    assert_includes ops, 'MOVE'
    assert_includes ops, 'PICKUP'
    assert_equal %w[GENERATOR COMMAND ARTILLERY].sort, activated_stations(result[:steps])
  end

  private

  def activated_stations(steps)
    steps.select { |step| step['op'] == 'INTERACT' && step['action'] == 'ACTIVATE' }
      .map { |step| step['target'] }
      .sort
  end
end
