# Converts internal actions to the fixed visual plan contract.

class PlanFormatter
  VALID_OPS = %w[MOVE PICKUP DROP INTERACT].freeze
  VALID_INTERACTIONS = %w[OPEN_DOOR REPAIR ACTIVATE RECHARGE].freeze

  def initialize(scenario)
    @scenario = scenario
  end

  def format(actions)
    actions.map { |action| format_action(action) }
  end

  private

  def format_action(action)
    case action.fetch(:type).to_sym
    when :move
      {
        'op' => 'MOVE',
        'from' => action.fetch(:from),
        'to' => action.fetch(:to),
        'cost' => action.fetch(:cost)
      }
    when :pickup
      { 'op' => 'PICKUP', 'item' => action.fetch(:item), 'cost' => action.fetch(:cost) }
    when :drop
      { 'op' => 'DROP', 'item' => action.fetch(:item), 'cost' => action.fetch(:cost) }
    when :open_door
      interact(action.fetch(:door), 'OPEN_DOOR', action)
    when :repair
      interact(action.fetch(:panel), 'REPAIR', action.merge(consumes: action.fetch(:material)))
    when :activate
      interact(action.fetch(:station), 'ACTIVATE', action)
    when :recharge
      interact(action.fetch(:charger), 'RECHARGE', action)
    else
      raise ArgumentError, "Cannot format action #{action[:type]}"
    end
  end

  def interact(target, interaction, action)
    result = {
      'op' => 'INTERACT',
      'target' => target,
      'action' => interaction,
      'cost' => action.fetch(:cost)
    }
    result['consumes'] = action.fetch(:consumes) if interaction == 'REPAIR'
    result
  end
end
