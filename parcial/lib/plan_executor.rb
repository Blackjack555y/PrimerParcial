# parcial/lib/plan_executor.rb
# Converts internal actions to CONTRATO-compliant visual operations

class PlanExecutor
  # Convert internal action sequence to visual operations (MOVE, PICKUP, DROP, INTERACT)
  def self.format_plan(internal_actions)
    internal_actions.map do |action|
      case action[:type]
      when :move
        {
          op: 'MOVE',
          from: action[:from_zone],
          to: action[:to_zone],
          cost: action[:cost]
        }
      when :pickup
        {
          op: 'PICKUP',
          item: action[:item],
          cost: action[:cost]
        }
      when :drop
        {
          op: 'DROP',
          item: action[:item],
          cost: action[:cost]
        }
      when :interact
        {
          op: 'INTERACT',
          target: action[:target],
          action: action[:action].to_s.upcase,
          cost: action[:cost]
        }
      else
        { op: 'UNKNOWN', cost: 0 }
      end
    end
  end

  # Verify plan against scenario constraints
  def self.validate_plan(plan, scenario)
    errors = []
    state = build_initial_state(scenario)

    plan.each_with_index do |step, idx|
      case step[:op]
      when 'MOVE'
        # Verify adjacent zones
        corridors = scenario['corridors'] || []
        valid = corridors.any? do |c|
          (c['from'] == state[:pos] && c['to'] == step[:to]) ||
            (c['from'] == step[:to] && c['to'] == state[:pos])
        end
        errors << "Step #{idx}: Invalid MOVE from #{state[:pos]} to #{step[:to]}" unless valid
        state[:pos] = step[:to]

      when 'PICKUP'
        # Verify item exists at current zone
        items = (scenario['materials'] || []) + (scenario['tools'] || []) + (scenario['keys'] || [])
        item = items.find { |i| i['id'] == step[:item] && i['zone'] == state[:pos] }
        errors << "Step #{idx}: Item #{step[:item]} not found at #{state[:pos]}" unless item
        state[:inventory][step[:item]] = (state[:inventory][step[:item]] || 0) + 1

      when 'DROP'
        errors << "Step #{idx}: Item #{step[:item]} not in inventory" unless state[:inventory][step[:item]].to_i > 0
        state[:inventory][step[:item]] -= 1

      when 'INTERACT'
        # Verify target exists and action is valid
        valid_actions = %w[OPEN_DOOR REPAIR ACTIVATE RECHARGE]
        errors << "Step #{idx}: Invalid action #{step[:action]}" unless valid_actions.include?(step[:action])
      end
    end

    errors
  end

  private

  def self.build_initial_state(scenario)
    {
      pos: scenario['robot']['zone'],
      battery: scenario['robot']['battery'],
      inventory: {}
    }
  end
end
