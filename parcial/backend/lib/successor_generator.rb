# Relevant successor generation for Applicable(state).

require_relative 'item_liveness'

class SuccessorGenerator
  def initialize(scenario)
    @scenario = scenario
    @liveness = ItemLiveness.new(scenario)
    @weights = build_weights
    @pickup_cost = scenario.action_costs.fetch('pickup', 1).to_i
    @drop_cost = scenario.action_costs.fetch('drop', 1).to_i
    @interact_cost = scenario.action_costs.fetch('interact', 2).to_i
    @recharge_cost = scenario.action_costs.fetch('recharge', 3).to_i
  end

  # drop_policy selects which DROP pruning strategy Applicable(s) uses:
  #   :needed_here (default) -- an item is offered as a DROP candidate
  #     unless it is still needed right here (opens an adjacent closed
  #     door, or repairs a present unrepaired panel). This is the policy
  #     design.md anticipates as potentially required for PANEL_B/PANEL_C's
  #     four-objects-into-capacity-3 squeeze.
  #   :dead_only -- ported from the reference Python solver. Never offers
  #     a live (still useful) carried item as a DROP candidate, no matter
  #     the zone; only items that are already dead cargo. Kept side by
  #     side with :needed_here (not swapped in silently) so both can be
  #     run against the real scenario and compared.
  def applicable(state, drop_policy: :dead_only)
    move_actions(state) + pickup_actions(state) + drop_actions(state, drop_policy) +
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

  def drop_actions(state, policy = :needed_here)
    case policy
    when :needed_here
      drop_actions_needed_here(state)
    when :dead_only
      drop_actions_dead_only(state)
    else
      raise ArgumentError, "Unknown drop policy: #{policy}"
    end
  end

  # Policy (a): full capacity + a useful item present here is required to
  # trigger a DROP at all, but once triggered, prefers dead cargo and
  # falls back to any carried item not needed in this exact zone -- so a
  # still-useful-elsewhere object can be dropped when capacity forces the
  # issue (design.md's PANEL_B/PANEL_C four-objects/capacity-3 case).
  def drop_actions_needed_here(state)
    carried_items = state.carried.keys
    useful_here = floor_items(state, state.pos).any? { |item, count| count.positive? && useful_item?(state, item) }
    capacity = @scenario.robot.fetch('cargo_capacity').to_i
    full = state.cargo_weight(@weights) >= capacity
    dead_items = carried_items.select { |item| dead_item?(state, item) }
    candidates = if dead_items.any?
                   dead_items
                 else
                   carried_items.reject { |item| needed_here?(state, item) }
                 end

    candidates.filter_map do |item|
      next if state.battery < @drop_cost
      next unless full && useful_here

      { type: :drop, item: item, cost: @drop_cost }
    end
  end

  # Policy (b), ported from the reference Python solver: only ever offers
  # to DROP cargo that is already dead. A live/useful carried item is
  # never a candidate, even at full capacity with a useful item waiting on
  # the floor here. If no dead cargo is carried, no DROP is generated.
  def drop_actions_dead_only(state)
    capacity = @scenario.robot.fetch('cargo_capacity').to_i
    return [] unless state.cargo_weight(@weights) >= capacity

    any_item_here = floor_items(state, state.pos).any? { |_item, count| count.positive? }
    return [] unless any_item_here

    dead_items = state.carried.keys.select { |item| dead_item?(state, item) }
    dead_items.filter_map do |item|
      next if state.battery < @drop_cost

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
    @liveness.useful?(state, item)
  end

  def dead_item?(state, item)
    @liveness.dead?(state, item)
  end

  def needed_here?(state, item)
    door = @scenario.doors.find do |candidate|
      candidate['key'] == item && candidate['between'].include?(state.pos) && !state.door_open?(candidate['id'])
    end
    return true if door

    @scenario.panels.any? do |panel|
      next false if state.panel_repaired?(panel['id'])
      next false unless panel['zone'] == state.pos

      requirements = panel.fetch('requires')
      requirements['tool'] == item || requirements['material'] == item
    end
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
