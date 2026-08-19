require_relative 'test_helper'

class CoreModelTest < Minitest::Test
  def setup
    @scenario = Scenario.from_file(SCENARIO_PATH)
    @model = TransitionModel.new(@scenario)
    @generator = SuccessorGenerator.new(@scenario)
    @initial = State.initial(@scenario)
  end

  def test_initial_state_matches_scenario
    assert_equal 'Z1', @initial.pos
    assert_equal 55, @initial.battery
    assert_equal 1, @initial.floor_count('Z1', 'KEY1')
    assert_equal 2, @initial.floor_count('Z2', 'FUSE')
    assert_empty @initial.carried
  end

  def test_states_are_canonical
    first = State.new(pos: 'Z1', battery: 40, carried: { 'KEY1' => 1, 'CHIP' => 1 }, floor: {}, doors_open: [], panels_repaired: [], stations_online: [])
    second = State.new(pos: 'Z1', battery: 40, carried: { 'CHIP' => 1, 'KEY1' => 1 }, floor: {}, doors_open: [], panels_repaired: [], stations_online: [])

    assert_equal first, second
    assert_equal first.hash, second.hash
  end

  def test_closed_door_blocks_move_until_key_is_carried_and_door_opened
    refute @generator.applicable(@initial).any? { |action| action[:type] == :move && action[:to] == 'Z2' }

    pickup = find_action(@initial, type: :pickup, item: 'KEY1')
    with_key = @model.apply(@initial, pickup)
    open = find_action(with_key, type: :open_door, door: 'DOOR1')
    with_door = @model.apply(with_key, open)
    move = find_action(with_door, type: :move, to: 'Z2')
    at_storage = @model.apply(with_door, move)

    assert_equal 'Z2', at_storage.pos
    assert_equal 48, at_storage.battery
    assert at_storage.door_open?('DOOR1')
  end

  def test_drop_and_recharge_change_the_expected_state_only
    full = State.new(
      pos: 'Z1',
      battery: 40,
      carried: { 'KEY1' => 1, 'KEY2' => 1, 'KEY3' => 1 },
      floor: { 'Z1' => { 'FUSE' => 1 } },
      doors_open: ['DOOR1'],
      panels_repaired: [],
      stations_online: []
    )
    drop = find_action(full, type: :drop, item: 'KEY1')
    after_drop = @model.apply(full, drop)

    refute after_drop.carried?('KEY1')
    assert_equal 1, after_drop.floor_count('Z1', 'KEY1')
    assert full.carried?('KEY1'), 'State must remain immutable'

    charger_state = State.new(pos: 'Z3', battery: 20, carried: {}, floor: {}, doors_open: [], panels_repaired: [], stations_online: [])
    recharge = find_action(charger_state, type: :recharge)
    charged = @model.apply(charger_state, recharge)
    assert_equal 100, charged.battery
  end

  private

  def find_action(state, expected)
    action = @generator.applicable(state).find { |candidate| expected.all? { |key, value| candidate[key] == value } }
    refute_nil action, "Missing action #{expected.inspect}"
    action
  end
end
