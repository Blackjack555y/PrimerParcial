#!/usr/bin/env ruby
# parcial/config.ru
# Rack configuration for Sinatra app

require_relative 'app'

run Sinatra::Application
