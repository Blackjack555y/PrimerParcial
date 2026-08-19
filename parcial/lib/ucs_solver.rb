# Uniform Cost Search over the implicit facility-state graph.

require_relative 'state'
require_relative 'transition_model'
require_relative 'successor_generator'
require_relative 'item_liveness'
require_relative 'plan_formatter'

class UcsSolver
  MAX_EXPANSIONS = 100_000
  Node = Struct.new(:state, :cost, :parent, :action, keyword_init: true)

  # drop_policy is forwarded to SuccessorGenerator#applicable as-is
  # (:needed_here or :dead_only, see successor_generator.rb). max_expansions
  # lets callers budget a run explicitly instead of always trusting
  # MAX_EXPANSIONS, e.g. to compare drop policies under the same limit.
  def initialize(scenario, drop_policy: :dead_only, max_expansions: MAX_EXPANSIONS)
    @scenario = scenario
    @transition_model = TransitionModel.new(scenario)
    @successor_generator = SuccessorGenerator.new(scenario)
    @liveness = ItemLiveness.new(scenario)
    @formatter = PlanFormatter.new(scenario)
    @drop_policy = drop_policy
    @max_expansions = max_expansions
  end

  def solve
    initial = State.initial(@scenario)
    root = Node.new(state: initial, cost: 0, parent: nil, action: nil)
    queue = MinPriorityQueue.new
    queue.push(root)
    labels = { initial.canonical_key(@liveness) => [[initial.battery, 0]] }
    expanded = 0

    until queue.empty?
      node = queue.pop
      key = node.state.canonical_key(@liveness)
      next unless current_label?(labels, key, node.state.battery, node.cost)
      next if dominated_by_other_label?(labels, key, node.state.battery, node.cost)

      expanded += 1
      if expanded > @max_expansions
        return {
          solution_found: false,
          total_cost: 0,
          steps: [],
          message: "Search limit reached after #{@max_expansions} expansions"
        }
      end

      if node.state.goal?(@scenario.goal.fetch('stations_online', []))
        actions = reconstruct_actions(node)
        steps = @formatter.format(actions)
        return {
          solution_found: true,
          total_cost: node.cost,
          steps: steps,
          message: "Solution found after #{expanded} expansions"
        }
      end

      @successor_generator.applicable(node.state, drop_policy: @drop_policy).each do |action|
        successor = @transition_model.apply(node.state, action)
        next_cost = node.cost + action.fetch(:cost).to_i
        next unless register_label(labels, successor, next_cost)

        queue.push(Node.new(state: successor, cost: next_cost, parent: node, action: action))
      end
    end

    {
      solution_found: false,
      total_cost: 0,
      steps: [],
      message: "No solution found after #{expanded} expansions"
    }
  end

  private

  def reconstruct_actions(node)
    actions = []
    current = node
    while current&.action
      actions << current.action
      current = current.parent
    end
    actions.reverse
  end

  def register_label(labels, state, cost)
    key = state.canonical_key(@liveness)
    labels[key] ||= []
    return false if labels[key].any? { |battery, known_cost| battery >= state.battery && known_cost <= cost }

    labels[key].reject! { |battery, known_cost| state.battery >= battery && cost <= known_cost }
    labels[key] << [state.battery, cost]
    true
  end

  def current_label?(labels, key, battery, cost)
    labels.fetch(key, []).include?([battery, cost])
  end

  def dominated_by_other_label?(labels, key, battery, cost)
    labels.fetch(key, []).any? do |other_battery, other_cost|
      other_cost <= cost && other_battery >= battery &&
        (other_cost < cost || other_battery > battery)
    end
  end
end

class MinPriorityQueue
  def initialize
    @items = []
    @sequence = 0
  end

  def push(item)
    @sequence += 1
    @items << [item.cost, @sequence, item]
    bubble_up(@items.length - 1)
  end

  def pop
    raise IndexError, 'Priority queue is empty' if empty?

    result = @items.first[2]
    last = @items.pop
    unless @items.empty?
      @items[0] = last
      bubble_down(0)
    end
    result
  end

  def empty?
    @items.empty?
  end

  private

  def before?(left, right)
    left[0] < right[0] || (left[0] == right[0] && left[1] < right[1])
  end

  def bubble_up(index)
    while index.positive?
      parent = (index - 1) / 2
      break unless before?(@items[index], @items[parent])

      @items[index], @items[parent] = @items[parent], @items[index]
      index = parent
    end
  end

  def bubble_down(index)
    loop do
      left = index * 2 + 1
      right = left + 1
      smallest = index
      smallest = left if left < @items.length && before?(@items[left], @items[smallest])
      smallest = right if right < @items.length && before?(@items[right], @items[smallest])
      break if smallest == index

      @items[index], @items[smallest] = @items[smallest], @items[index]
      index = smallest
    end
  end
end
