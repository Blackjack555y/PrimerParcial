# backend/models/state.rb
# Represents the immutable state of the facility at any point in time
#
# State tuple: (robot_pos, battery, inventory, world_state)
# where world_state = { doors_open, panels_repaired, stations_active, charger_used }

class State
  attr_reader :robot_pos, :battery, :inventory, :world_state, :g_cost

  # @param robot_pos [String] Current zone identifier (e.g., "Z1")
  # @param battery [Integer] Remaining battery percentage (0-100)
  # @param inventory [Hash] Items carried: { item_id => count | item_type => count }
  # @param world_state [Hash] Facility state: { doors_open: Set, panels_repaired: Set, stations_active: Set }
  # @param g_cost [Float] Cumulative cost from start state
  def initialize(robot_pos, battery, inventory = {}, world_state = {}, g_cost = 0)
    @robot_pos = robot_pos
    @battery = [battery, 100].min  # Cap at 100
    @inventory = normalize_inventory(inventory)
    @world_state = normalize_world_state(world_state)
    @g_cost = g_cost
    @hash = compute_hash
  end

  # Create a successor state from an action
  # Internal action format: { type, cost, effects }
  def transition(action)
    cost = action[:cost] || 1
    effects = action[:effects] || {}

    new_pos = effects[:new_pos] || @robot_pos
    new_battery = effects[:new_battery] || @battery
    new_inventory = effects[:new_inventory] || @inventory.dup
    new_world = deep_merge(@world_state, effects[:new_world_state] || {})

    State.new(new_pos, new_battery, new_inventory, new_world, @g_cost + cost)
  end

  # State equivalence: two states are equal if they represent identical facility conditions
  def ==(other)
    return false unless other.is_a?(State)
    @robot_pos == other.robot_pos &&
      @battery == other.battery &&
      canonical_inventory == other.send(:canonical_inventory) &&
      canonical_world == other.send(:canonical_world)
  end

  def hash
    @hash
  end

  def eql?(other)
    self == other
  end

  # Derived information: current cargo weight (materials count as 1 unit each)
  def cargo_weight
    @inventory.values.sum
  end

  # Remaining cargo capacity (arbitrary limit: 10 units)
  def remaining_capacity
    10 - cargo_weight
  end

  # Goal test: all 3 panels repaired and all 3 stations active
  def goal?
    panels_repaired_count == 3 && stations_active_count == 3
  end

  def panels_repaired_count
    @world_state[:panels_repaired]&.size || 0
  end

  def stations_active_count
    @world_state[:stations_active]&.size || 0
  end

  def door_open?(door_id)
    @world_state[:doors_open]&.include?(door_id) || false
  end

  def panel_repaired?(panel_id)
    @world_state[:panels_repaired]&.include?(panel_id) || false
  end

  def station_active?(station_id)
    @world_state[:stations_active]&.include?(station_id) || false
  end

  def has_item?(item_id)
    @inventory[item_id].to_i > 0
  end

  def item_count(item_id)
    @inventory[item_id].to_i
  end

  def to_h
    {
      robot_pos: @robot_pos,
      battery: @battery,
      inventory: @inventory,
      world_state: @world_state,
      g_cost: @g_cost
    }
  end

  private

  def normalize_inventory(inv)
    inv.is_a?(Hash) ? inv.dup : {}
  end

  def normalize_world_state(ws)
    {
      doors_open: Set.new(ws[:doors_open] || []),
      panels_repaired: Set.new(ws[:panels_repaired] || []),
      stations_active: Set.new(ws[:stations_active] || [])
    }
  end

  def canonical_inventory
    @inventory.sort.to_h
  end

  def canonical_world
    {
      doors_open: @world_state[:doors_open].sort.to_a,
      panels_repaired: @world_state[:panels_repaired].sort.to_a,
      stations_active: @world_state[:stations_active].sort.to_a
    }
  end

  def deep_merge(base, updates)
    result = base.dup
    updates.each { |k, v| result[k] = v }
    result
  end

  def compute_hash
    Digest::SHA256.hexdigest(
      "#{@robot_pos}:#{@battery}:#{canonical_inventory}:#{canonical_world}"
    ).to_i(16)
  end
end
