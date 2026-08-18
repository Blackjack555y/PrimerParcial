# backend/controllers/api/solve_controller.rb
module Api
  class SolveController < ApplicationController
    protect_from_forgery with: :null_session
    before_action :validate_scenario

    # POST /api/solve
    # Solves the emergency facility control problem
    def solve
      solver = UcsSolver.new(@scenario)
      result = solver.solve

      if result[:solution_found]
        plan = format_plan(result[:steps])
        render json: {
          solution_found: true,
          total_cost: result[:total_cost],
          steps: plan,
          message: result[:message]
        }, status: :ok
      else
        render json: {
          solution_found: false,
          total_cost: 0,
          steps: [],
          message: result[:message]
        }, status: :unprocessable_entity
      end
    rescue StandardError => e
      render json: {
        solution_found: false,
        total_cost: 0,
        steps: [],
        message: "Error: #{e.message}"
      }, status: :internal_server_error
    end

    private

    def validate_scenario
      @scenario = request.body.read
      @scenario = JSON.parse(@scenario) if @scenario.is_a?(String)

      required_keys = %w[zones corridors robot]
      missing = required_keys - @scenario.keys
      raise ArgumentError, "Missing required fields: #{missing.join(', ')}" if missing.any?
    rescue JSON::ParserError => e
      render json: { error: "Invalid JSON: #{e.message}" }, status: :bad_request
    rescue ArgumentError => e
      render json: { error: e.message }, status: :bad_request
    end

    # Convert internal action format to CONTRATO-compliant visual operations
    # Visual operations: MOVE, PICKUP, DROP, INTERACT
    def format_plan(internal_actions)
      internal_actions.map do |action|
        case action[:type]
        when :move
          {
            op: "MOVE",
            from: action[:from_zone],
            to: action[:to_zone],
            cost: action[:cost]
          }
        when :pickup
          {
            op: "PICKUP",
            item: action[:item],
            cost: action[:cost]
          }
        when :drop
          {
            op: "DROP",
            item: action[:item],
            cost: action[:cost]
          }
        when :interact
          {
            op: "INTERACT",
            target: action[:target],
            action: action[:action].to_s.upcase,
            cost: action[:cost]
          }
        else
          { op: "UNKNOWN", cost: 0 }
        end
      end
    end
  end
end
