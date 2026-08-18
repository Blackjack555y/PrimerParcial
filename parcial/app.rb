# parcial/app.rb
# Lightweight Sinatra app for the facility control solver
# Faster alternative to full Rails for quick testing

require 'sinatra'
require 'json'
require 'digest'
require 'set'
require 'fileutils'

# Load solver components
require_relative 'lib/state'
require_relative 'lib/ucs_solver'
require_relative 'lib/plan_executor'

set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, File.join(__dir__, 'public')

# Health check
get '/api/health' do
  content_type :json
  { status: 'ok', timestamp: Time.now.iso8601 }.to_json
end

# Get demo scenario
get '/demo-scenario.json' do
  content_type :json
  File.read(File.join(__dir__, 'demo_scenario.json'))
end

# Serve index.html for root
get '/' do
  content_type :html
  File.read(File.join(settings.public_folder, 'index.html'))
end

# Solve endpoint
post '/api/solve' do
  content_type :json
  
  begin
    scenario = JSON.parse(request.body.read)
    validate_scenario(scenario)

    solver = UcsSolver.new(scenario)
    result = solver.solve

    {
      solution_found: result[:solution_found],
      total_cost: result[:total_cost],
      steps: result[:steps],
      message: result[:message]
    }.to_json
  rescue JSON::ParserError => e
    status 400
    { error: "Invalid JSON: #{e.message}" }.to_json
  rescue ArgumentError => e
    status 400
    { error: e.message }.to_json
  rescue StandardError => e
    status 500
    { error: "Server error: #{e.message}", backtrace: e.backtrace.first(5) }.to_json
  end
end


private

def validate_scenario(scenario)
  required = %w[zones corridors robot]
  missing = required - scenario.keys
  raise ArgumentError, "Missing fields: #{missing.join(', ')}" if missing.any?
end
