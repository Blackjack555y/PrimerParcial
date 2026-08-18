# backend/services/ucs_solver.rb
# Uniform Cost Search implementation for optimal facility control planning
#
# Key principles:
# - Expand nodes in order of increasing path cost (g(n))
# - Maintain CLOSED set to detect revisited states
# - Return optimal plan when goal found

require 'set'
require 'priority_queue'

class UcsSolver
  MAX_ITERATIONS = 10_000
  MAX_PLAN_LENGTH = 200

  def initialize(scenario)
    @scenario = scenario
    @iterations = 0
    @closed = Set.new
    @open = PriorityQueue.new  # min-heap by g_cost
  end

  # Solve the facility problem using UCS
  # Returns: { solution_found: bool, total_cost: float, steps: [internal_actions], message: string }
  def solve
    initial_state = build_initial_state
    
    return { solution_found: false, total_cost: 0, steps: [], message: "Goal already satisfied" } if initial_state.goal?

    @open.push(initial_state, initial_state.g_cost)

    while @open.any? && @iterations < MAX_ITERATIONS
      @iterations += 1

      current = @open.pop
      state_hash = hash_state(current)

      next if @closed.include?(state_hash)
      @closed.add(state_hash)

      if current.goal?
        return format_solution(current)
      end

      # Expand successors
      applicable_actions(current).each do |action|
        successor = current.transition(action)
        successor_hash = hash_state(successor)

        next if @closed.include?(successor_hash)
        @open.push(successor, successor.g_cost)
      end
    end

    { solution_found: false, total_cost: 0, steps: [], message: "No solution found (max iterations: #{MAX_ITERATIONS})" }
  end

  private

  def build_initial_state
    State.new(
      @scenario['robot']['zone'],
      @scenario['robot']['battery'].to_i,
      {},
      {
        doors_open: Set.new,
        panels_repaired: Set.new,
        stations_active: Set.new
      }
    )
  end

  # Generate applicable actions from current state
  # Restriction: only generate DROP when cargo is full or strategically needed
  def applicable_actions(state)
    actions = []

    # Action: MOVE to adjacent zone
    adjacent_zones(state.robot_pos).each do |next_zone|
      cost = corridor_cost(state.robot_pos, next_zone)
      actions << {
        type: :move,
        to: next_zone,
        cost: cost,
        effects: {
          new_pos: next_zone,
          new_battery: state.battery - 1  # Battery drain
        }
      }
    end

    # Action: PICKUP item (materials, keys, tools)
    items_here(state.robot_pos).each do |item|
      if state.remaining_capacity > 0
        actions << {
          type: :pickup,
          item: item[:id],
          cost: 1,
          effects: {
            new_inventory: update_inventory(state.inventory, item[:id], +1)
          }
        }
      end
    end

    # Action: DROP item (only if strategic)
    if state.cargo_weight >= 8  # Only drop when nearly full
      state.inventory.each do |item_id, count|
        if count > 0
          actions << {
            type: :drop,
            item: item_id,
            cost: 1,
            effects: {
              new_inventory: update_inventory(state.inventory, item_id, -1)
            }
          }
        end
      end
    end

    # Action: INTERACT with doors, panels, stations
    doors_here(state.robot_pos).each do |door|
      if !state.door_open?(door[:id]) && state.has_item?(door[:key_id])
        actions << {
          type: :interact,
          target: door[:id],
          action: :open_door,
          cost: 2,
          effects: {
            new_world_state: {
              doors_open: state.world_state[:doors_open] + [door[:id]]
            }
          }
        }
      end
    end

    panels_here(state.robot_pos).each do |panel|
      if !state.panel_repaired?(panel[:id])
        required_items = panel[:required_materials].keys
        if required_items.all? { |item| state.has_item?(item) }
          new_inventory = state.inventory.dup
          required_items.each { |item| new_inventory[item] = (new_inventory[item] || 0) - 1 }

          actions << {
            type: :interact,
            target: panel[:id],
            action: :repair,
            cost: 3,
            effects: {
              new_inventory: new_inventory,
              new_world_state: {
                panels_repaired: state.world_state[:panels_repaired] + [panel[:id]]
              }
            }
          }
        end
      end
    end

    stations_here(state.robot_pos).each do |station|
      if !state.station_active?(station[:id])
        # Check if all required panels are repaired
        required_panels = station[:required_panels]
        if required_panels.all? { |panel_id| state.panel_repaired?(panel_id) }
          actions << {
            type: :interact,
            target: station[:id],
            action: :activate,
            cost: 2,
            effects: {
              new_world_state: {
                stations_active: state.world_state[:stations_active] + [station[:id]]
              }
            }
          }
        end
      end
    end

    # Action: RECHARGE at charger
    if charger_here?(state.robot_pos) && state.battery < 100
      actions << {
        type: :interact,
        target: "charger_#{state.robot_pos}",
        action: :recharge,
        cost: 5,
        effects: {
          new_battery: 100
        }
      }
    end

    actions
  end

  def adjacent_zones(zone)
    corridors = @scenario['corridors'] || []
    corridors
      .select { |c| c['from'] == zone || c['to'] == zone }
      .map { |c| c['from'] == zone ? c['to'] : c['from'] }
  end

  def corridor_cost(from, to)
    corridors = @scenario['corridors'] || []
    corridor = corridors.find { |c| (c['from'] == from && c['to'] == to) || (c['from'] == to && c['to'] == from) }
    corridor ? corridor['cost'].to_i : 1
  end

  def items_here(zone)
    items = []
    ((@scenario['materials'] || []) + (@scenario['tools'] || []) + (@scenario['keys'] || []))
      .select { |item| item['zone'] == zone }
      .each { |item| items << item }
    items
  end

  def doors_here(zone)
    (@scenario['doors'] || []).select { |door| door['zone'] == zone }
  end

  def panels_here(zone)
    (@scenario['panels'] || []).select { |panel| panel['zone'] == zone }
  end

  def stations_here(zone)
    (@scenario['stations'] || []).select { |station| station['zone'] == zone }
  end

  def charger_here?(zone)
    (@scenario['zones'] || []).find { |z| z['id'] == zone }&.fetch('charger', false) || false
  end

  def update_inventory(inv, item_id, delta)
    new_inv = inv.dup
    new_inv[item_id] = (new_inv[item_id] || 0) + delta
    new_inv.delete(item_id) if new_inv[item_id] <= 0
    new_inv
  end

  def hash_state(state)
    state.hash
  end

  def format_solution(state)
    # Reconstruct plan by backtracking through states
    # For now, return accumulated cost
    {
      solution_found: true,
      total_cost: state.g_cost,
      steps: [],  # TODO: implement backtracking
      message: "Solution found in #{@iterations} iterations"
    }
  end
end

# Priority queue implementation (Ruby doesn't have built-in min-heap)
class PriorityQueue
  def initialize
    @queue = []
  end

  def push(item, priority)
    @queue << [priority, item]
    @queue.sort_by! { |p, _| p }
  end

  def pop
    @queue.shift&.last
  end

  def any?
    @queue.any?
  end

  def size
    @queue.size
  end
end
