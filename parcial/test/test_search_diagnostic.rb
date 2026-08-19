require_relative 'test_helper'

class SearchDiagnosticTest < Minitest::Test
  MAX_EXPANSIONS = 2_000

  def test_bounded_search_reports_growth_without_hanging
    scenario = Scenario.from_file(SCENARIO_PATH)
    model = TransitionModel.new(scenario)
    generator = SuccessorGenerator.new(scenario)
    initial = State.initial(scenario)

    frontier = [[initial, 0]]
    seen = { initial.key => true }
    expanded = 0
    generated = 0
    max_frontier = frontier.length
    action_counts = Hash.new(0)
    goal_reached = false

    until frontier.empty? || expanded >= MAX_EXPANSIONS
      state, depth = frontier.shift
      expanded += 1

      if state.goal?(scenario.goal.fetch('stations_online'))
        goal_reached = true
        break
      end

      generator.applicable(state).each do |action|
        action_counts[action[:type]] += 1
        successor = model.apply(state, action)
        generated += 1
        next if seen.key?(successor.key)

        seen[successor.key] = true
        frontier << [successor, depth + 1]
      end
      max_frontier = [max_frontier, frontier.length].max
    end

    puts "DIAGNOSTIC expanded=#{expanded} generated=#{generated} unique=#{seen.length} " \
         "frontier=#{frontier.length} max_frontier=#{max_frontier} goal=#{goal_reached}"
    puts "DIAGNOSTIC actions=#{action_counts.sort.to_h.inspect}"

    assert_operator expanded, :<=, MAX_EXPANSIONS
    assert_operator seen.length, :>, 0
  end
end
