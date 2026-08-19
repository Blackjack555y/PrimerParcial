# Decides whether an item can still enable a future action or change its cost.
# Shared by SuccessorGenerator (pickup/drop pruning) and TransitionModel
# (dropping dead floor items from the canonical state).

class ItemLiveness
  def initialize(scenario)
    @scenario = scenario
  end

  def useful?(state, item)
    door = @scenario.doors.find { |candidate| candidate['key'] == item }
    return !state.door_open?(door['id']) if door

    panels = @scenario.panels.select do |panel|
      requirements = panel.fetch('requires')
      requirements['tool'] == item || requirements['material'] == item
    end
    panels.any? { |panel| !state.panel_repaired?(panel['id']) }
  end

  def dead?(state, item)
    !useful?(state, item)
  end
end
