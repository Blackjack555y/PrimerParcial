# Scenario loader and read-only access to the world definition.

require 'json'

class Scenario
  attr_reader :data

  def initialize(data)
    @data = deep_freeze(data)
    validate!
  end

  def self.from_file(path)
    new(JSON.parse(File.read(path)))
  end

  def robot
    data.fetch('robot')
  end

  def zones
    data.fetch('zones', [])
  end

  def corridors
    data.fetch('corridors', [])
  end

  def doors
    data.fetch('doors', [])
  end

  def keys
    data.fetch('keys', [])
  end

  def tools
    data.fetch('tools', [])
  end

  def materials
    data.fetch('materials', [])
  end

  def panels
    data.fetch('panels', [])
  end

  def stations
    data.fetch('stations', [])
  end

  def chargers
    data.fetch('chargers', [])
  end

  def goal
    data.fetch('goal', {})
  end

  def action_costs
    data.fetch('action_costs', {})
  end

  def zone(id)
    zones.find { |item| item['id'] == id }
  end

  def corridor(from, to)
    corridors.find { |item| item['from'] == from && item['to'] == to }
  end

  def door(id)
    doors.find { |item| item['id'] == id }
  end

  def panel(id)
    panels.find { |item| item['id'] == id }
  end

  def station(id)
    stations.find { |item| item['id'] == id }
  end

  def charger(id)
    chargers.find { |item| item['id'] == id }
  end

  def item_definitions
    keys + tools + materials
  end

  private

  def validate!
    %w[robot zones corridors].each do |key|
      raise ArgumentError, "Scenario missing #{key}" unless data.key?(key)
    end

    raise ArgumentError, 'Robot start zone is missing' unless robot['start']
    raise ArgumentError, 'Robot battery_start is missing' unless robot['battery_start']
    raise ArgumentError, 'Robot battery_max is missing' unless robot['battery_max']
    raise ArgumentError, 'Robot cargo_capacity is missing' unless robot['cargo_capacity']
  end

  def deep_freeze(value)
    case value
    when Hash
      value.each { |key, item| deep_freeze(key); deep_freeze(item) }
    when Array
      value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end
end
