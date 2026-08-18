# Deterministic state transitions for legal internal actions.

require_relative 'state'

class TransitionModel
  def initialize(scenario)
    @scenario = scenario
  end

  def apply(state, action)
    type = action.fetch(:type).to_sym
    cost = action.fetch(:cost).to_i
    raise ArgumentError, 'Action cost must be positive' unless cost.positive?
    raise ArgumentError, 'Insufficient battery' if state.battery < cost

    case type
    when :move
      move(state, action, cost)
    when :pickup
      pickup(state, action, cost)
    when :drop
      drop(state, action, cost)
    when :open_door
      open_door(state, action, cost)
    when :repair
      repair(state, action, cost)
    when :activate
      activate(state, action, cost)
    when :recharge
      recharge(state, action, cost)
    else
      raise ArgumentError, "Unknown action type: #{type}"
    end
  end

  private

  def move(state, action, cost)
    from = action.fetch(:from, state.pos)
    to = action.fetch(:to)
    corridor = @scenario.corridor(from, to)
    raise ArgumentError, 'No directed corridor' unless state.pos == from && corridor

    door_id = corridor['door']
    raise ArgumentError, 'Door is closed' if door_id && !state.door_open?(door_id)

    build_state(state, pos: to, battery: state.battery - cost)
  end

  def pickup(state, action, cost)
    item = action.fetch(:item).to_s
    raise ArgumentError, 'Item is not on the floor' unless state.floor_count(state.pos, item).positive?

    floor = remove_item_from_floor(state.floor, state.pos, item)
    carried = add_item(state.carried, item)
    build_state(state, carried: carried, floor: floor, battery: state.battery - cost)
  end

  def drop(state, action, cost)
    item = action.fetch(:item).to_s
    raise ArgumentError, 'Item is not carried' unless state.carried?(item)

    carried = remove_item_from_carried(state.carried, item)
    floor = add_item_to_floor(state.floor, state.pos, item)
    build_state(state, carried: carried, floor: floor, battery: state.battery - cost)
  end

  def open_door(state, action, cost)
    door = @scenario.door(action.fetch(:door).to_s)
    raise ArgumentError, 'Unknown door' unless door
    raise ArgumentError, 'Door is already open' if state.door_open?(door['id'])
    raise ArgumentError, 'Required key is not carried' unless state.carried?(door['key'])
    raise ArgumentError, 'Robot is not beside the door' unless door['between'].include?(state.pos)

    build_state(state, doors_open: state.doors_open + [door['id']], battery: state.battery - cost)
  end

  def repair(state, action, cost)
    panel = @scenario.panel(action.fetch(:panel).to_s)
    raise ArgumentError, 'Unknown panel' unless panel
    raise ArgumentError, 'Panel is already repaired' if state.panel_repaired?(panel['id'])
    raise ArgumentError, 'Robot is not at the panel' unless panel['zone'] == state.pos

    tool = panel.fetch('requires').fetch('tool')
    material = action.fetch(:material).to_s
    required_material = panel.fetch('requires').fetch('material')
    raise ArgumentError, 'Required tool is not carried' unless state.carried?(tool)
    raise ArgumentError, 'Wrong repair material' unless material == required_material
    raise ArgumentError, 'Required material is not carried' unless state.carried?(material)

    build_state(
      state,
      carried: remove_item_from_carried(state.carried, material),
      panels_repaired: state.panels_repaired + [panel['id']],
      battery: state.battery - cost
    )
  end

  def activate(state, action, cost)
    station = @scenario.station(action.fetch(:station).to_s)
    raise ArgumentError, 'Unknown station' unless station
    raise ArgumentError, 'Station is already online' if state.station_online?(station['id'])
    raise ArgumentError, 'Robot is not at the station' unless station['zone'] == state.pos

    requirements = station.fetch('requires', {})
    panels_ok = requirements.fetch('panels_ok', [])
    stations_online = requirements.fetch('stations_online', [])
    unless panels_ok.all? { |panel| state.panel_repaired?(panel) } &&
           stations_online.all? { |required| state.station_online?(required) }
      raise ArgumentError, 'Station dependencies are incomplete'
    end

    build_state(state, stations_online: state.stations_online + [station['id']], battery: state.battery - cost)
  end

  def recharge(state, action, cost)
    charger = @scenario.charger(action.fetch(:charger).to_s)
    raise ArgumentError, 'Unknown charger' unless charger
    raise ArgumentError, 'Robot is not at the charger' unless charger['zone'] == state.pos
    raise ArgumentError, 'Battery is already full' if state.battery >= @scenario.robot.fetch('battery_max').to_i

    build_state(state, battery: @scenario.robot.fetch('battery_max').to_i)
  end

  def build_state(state, **changes)
    State.new(
      pos: changes.fetch(:pos, state.pos),
      battery: changes.fetch(:battery, state.battery),
      carried: changes.fetch(:carried, state.carried),
      floor: changes.fetch(:floor, state.floor),
      doors_open: changes.fetch(:doors_open, state.doors_open),
      panels_repaired: changes.fetch(:panels_repaired, state.panels_repaired),
      stations_online: changes.fetch(:stations_online, state.stations_online)
    )
  end

  def add_item(items, item)
    items.merge(item => items.fetch(item, 0) + 1)
  end

  def remove_item(items, item)
    result = items.transform_values(&:dup)
    result[item] -= 1
    result.delete(item) if result[item] <= 0
    result
  end

  def remove_item_from_carried(carried, item)
    remove_item(carried, item)
  end

  def remove_item_from_floor(floor, zone, item)
    result = floor.transform_values(&:dup)
    result[zone] = remove_item(result.fetch(zone, {}), item)
    result.delete(zone) if result[zone].empty?
    result
  end

  def add_item_to_floor(floor, zone, item)
    result = floor.transform_values(&:dup)
    result[zone] = add_item(result.fetch(zone, {}), item)
    result
  end
end
