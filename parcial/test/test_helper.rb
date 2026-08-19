require 'minitest/autorun'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))

require 'scenario'
require 'state'
require 'transition_model'
require 'successor_generator'
require 'ucs_solver'

SCENARIO_PATH = File.join(ROOT, 'scenarios', 'scenario.json')
