# Relevant successor generation for Applicable(state).

class SuccessorGenerator
  def initialize(scenario)
    @scenario = scenario
    @weights = build_weights
    @pickup_cost = scenario.action_costs.fetch('pickup', 1).to_i
    @drop_cost = scenario.action_costs.fetch('drop', 1).to_i
    @interact_cost = scenario.action_costs.fetch('interact', 2).to_i
    @recharge_cost = scenario.action_costs.fetch('recharge', 3).to_i
  end

  def applicable(state)
    move_actions(state) + pickup_actions(state) + drop_actions(state) +
      door_actions(state) + repair_actions(state) + activate_actions(state) +
      recharge_actions(state)
  end

  def weights
    @weights
  end

  private

  def move_actions(state)
    @scenario.corridors
      .select { |corridor| corridor['from'] == state.pos }
      .filter_map do |corridor|
        door_id = corridor['door']
        next if door_id && !state.door_open?(door_id)

        cost = corridor['cost'].to_i
        next if state.battery < cost

        {
          type: :move,
          from: corridor['from'],
          to: corridor['to'],
          cost: cost
        }
      end
  end

  def pickup_actions(state)
    floor_items(state, state.pos).filter_map do |item, count|
      next unless count.positive?
      next unless useful_item?(state, item)
      next unless pickup_needed?(state, item)

      weight = @weights.fetch(item, 0)
      next if state.capacity_available(@scenario.robot.fetch('cargo_capacity').to_i, @weights) < weight
      next if state.battery < @pickup_cost

      { type: :pickup, item: item, cost: @pickup_cost }
    end
  end

  def drop_actions(state)
    carried_items = state.carried.keys
    useful_here = floor_items(state, state.pos).any? { |item, count| count.positive? && useful_item?(state, item) }
    capacity = @scenario.robot.fetch('cargo_capacity').to_i
    full = state.cargo_weight(@weights) >= capacity
    dead_items = carried_items.select { |item| dead_item?(state, item) }
    candidates = dead_items.empty? ? carried_items : dead_items

    candidates.filter_map do |item|
      next if state.battery < @drop_cost
      next unless full && useful_here

      { type: :drop, item: item, cost: @drop_cost }
    end
  end

  def door_actions(state)
    @scenario.doors.filter_map do |door|
      next if state.door_open?(door['id'])
      next unless door['between'].include?(state.pos)
      next unless state.carried?(door['key'])
      next if state.battery < @interact_cost

      { type: :open_door, door: door['id'], cost: @interact_cost }
    end
  end

  def repair_actions(state)
    @scenario.panels.filter_map do |panel|
      next if state.panel_repaired?(panel['id'])
      next unless panel['zone'] == state.pos

      requirements = panel.fetch('requires')
      material = requirements.fetch('material')
      next unless state.carried?(requirements.fetch('tool'))
      next unless state.carried?(material)
      next if state.battery < @interact_cost

      {
        type: :repair,
        panel: panel['id'],
        material: material,
        cost: @interact_cost
      }
    end
  end

  def activate_actions(state)
    @scenario.stations.filter_map do |station|
      next if state.station_online?(station['id'])
      next unless station['zone'] == state.pos

      requirements = station.fetch('requires', {})
      panels_ok = requirements.fetch('panels_ok', [])
      stations_online = requirements.fetch('stations_online', [])
      next unless panels_ok.all? { |panel| state.panel_repaired?(panel) }
      next unless stations_online.all? { |required| state.station_online?(required) }
      next if state.battery < @interact_cost

      { type: :activate, station: station['id'], cost: @interact_cost }
    end
  end

  def recharge_actions(state)
    @scenario.chargers.filter_map do |charger|
      next unless charger['zone'] == state.pos
      next if state.battery >= @scenario.robot.fetch('battery_max').to_i
      next if state.battery < @recharge_cost

      { type: :recharge, charger: charger['id'], cost: @recharge_cost }
    end
  end

  def floor_items(state, zone)
    state.floor.fetch(zone, {})
  end

  def useful_item?(state, item)
    door = @scenario.doors.find { |candidate| candidate['key'] == item }
    return !state.door_open?(door['id']) if door

    panels = @scenario.panels.select do |panel|
      requirements = panel.fetch('requires')
      requirements['tool'] == item || requirements['material'] == item
    end
    panels.any? { |panel| !state.panel_repaired?(panel['id']) }
  end

  def dead_item?(state, item)
    !useful_item?(state, item)
  end

  def pickup_needed?(state, item)
    material = @scenario.materials.find { |candidate| candidate['type'] == item }
    return true unless material

    outstanding = @scenario.panels
      .reject { |panel| state.panel_repaired?(panel['id']) }
      .count { |panel| panel.fetch('requires').fetch('material') == item }
    state.carried_count(item) < outstanding
  end

  def build_weights
    weights = {}
    @scenario.keys.each { |item| weights[item['id']] = item.fetch('weight', 0).to_i }
    @scenario.tools.each { |item| weights[item['id']] = item.fetch('weight', 0).to_i }
    @scenario.materials.each { |item| weights[item['type']] = item.fetch('weight', 0).to_i }
    weights
  end
end
