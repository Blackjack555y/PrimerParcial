# Immutable, canonical physical state for the facility.

class State
  attr_reader :pos, :battery, :carried, :floor, :doors_open,
              :panels_repaired, :stations_online

  def initialize(pos:, battery:, carried:, floor:, doors_open:, panels_repaired:, stations_online:)
    @pos = pos.to_s
    @battery = Integer(battery)
    @carried = freeze_counts(carried)
    @floor = freeze_floor(floor)
    @doors_open = freeze_set(doors_open)
    @panels_repaired = freeze_set(panels_repaired)
    @stations_online = freeze_set(stations_online)
    @key = build_key.freeze
    freeze
  end

  def self.initial(scenario)
    floor = Hash.new { |hash, zone| hash[zone] = {} }

    scenario.keys.each { |item| add_floor_item(floor, item['zone'], item['id']) }
    scenario.tools.each { |item| add_floor_item(floor, item['zone'], item['id']) }
    scenario.materials.each do |item|
      add_floor_item(floor, item['zone'], item['type'], item.fetch('count', 0).to_i)
    end

    new(
      pos: scenario.robot.fetch('start'),
      battery: scenario.robot.fetch('battery_start'),
      carried: {},
      floor: floor,
      doors_open: scenario.doors.select { |door| door['state'] == 'OPEN' }.map { |door| door['id'] },
      panels_repaired: scenario.panels.select { |panel| panel['state'] == 'REPAIRED' }.map { |panel| panel['id'] },
      stations_online: scenario.stations.select { |station| station['state'] == 'ONLINE' }.map { |station| station['id'] }
    )
  end

  def ==(other)
    other.is_a?(State) && key == other.key
  end
  alias eql? ==

  def hash
    key.hash
  end

  def key
    @key
  end

  def physical_key
    [pos, carried, floor, doors_open, panels_repaired, stations_online]
  end

  # Canonical key for CLOSED/dominance bookkeeping: identical to
  # physical_key except that floor items which can no longer enable or
  # cheapen any future action (per +liveness+) are left out. The floor
  # itself is never mutated -- two states that differ only in the
  # location of dead objects collapse to the same search key without
  # losing any physical information the transition model might still need.
  # State stays scenario-agnostic: the caller (UcsSolver) supplies an
  # ItemLiveness built from the scenario; State only asks it dead?(self, item).
  def canonical_key(liveness)
    filtered_floor = floor.each_with_object({}) do |(zone, items), result|
      kept = items.reject { |item, _count| liveness.dead?(self, item) }
      result[zone] = kept unless kept.empty?
    end
    [pos, carried, filtered_floor, doors_open, panels_repaired, stations_online]
  end

  def carried?(item)
    carried.fetch(item, 0).positive?
  end

  def carried_count(item)
    carried.fetch(item, 0)
  end

  def floor_count(zone, item)
    floor.fetch(zone, {}).fetch(item, 0)
  end

  def cargo_weight(weights)
    carried.sum { |item, count| weights.fetch(item, 0) * count }
  end

  def capacity_available(capacity, weights)
    capacity - cargo_weight(weights)
  end

  def door_open?(door_id)
    doors_open.include?(door_id)
  end

  def panel_repaired?(panel_id)
    panels_repaired.include?(panel_id)
  end

  def station_online?(station_id)
    stations_online.include?(station_id)
  end

  def goal?(goal_ids)
    goal_ids.all? { |station_id| station_online?(station_id) }
  end

  def to_h
    {
      pos: pos,
      battery: battery,
      carried: carried,
      floor: floor,
      doors_open: doors_open,
      panels_repaired: panels_repaired,
      stations_online: stations_online
    }
  end

  def self.add_floor_item(floor, zone, item, count = 1)
    return if count <= 0

    floor[zone] ||= {}
    floor[zone][item] = floor[zone].fetch(item, 0) + count
  end

  private_class_method :add_floor_item

  private

  def freeze_counts(counts)
    counts.each_with_object({}) do |(item, count), result|
      result[item.to_s] = Integer(count) if Integer(count).positive?
    end.sort.to_h.freeze
  end

  def freeze_floor(positions)
    positions.each_with_object({}) do |(zone, items), result|
      counts = freeze_counts(items)
      result[zone.to_s] = counts unless counts.empty?
    end.sort.to_h.freeze
  end

  def freeze_set(values)
    values.map(&:to_s).uniq.sort.freeze
  end

  def build_key
    [pos, battery, carried, floor, doors_open, panels_repaired, stations_online]
  end
end
