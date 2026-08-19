# Minimal HTTP server for the Emergency Control solver.
#
# Deliberately dependency-free: only Ruby core (Socket/TCPServer), no gems.
# Rack/Sinatra/WEBrick all require installing something, and gem installs
# cannot be assumed to work on the grading machine (see: AVG's SSL
# interception breaking `gem install` on this very machine). A hand-rolled
# HTTP/1.1 parser is a few dozen lines and has zero install-time risk.
#
# Usage: ruby server.rb [port]   (default port 3000)

require 'socket'
require 'json'

require_relative 'lib/scenario'
require_relative 'lib/ucs_solver'

DEFAULT_SCENARIO_PATH = File.join(__dir__, 'scenarios', 'scenario.json')
FRONTEND_DIR = File.join(__dir__, '..', 'frontend')
STATIC_FILES = {
  '/' => ['index.html', 'text/html; charset=utf-8'],
  '/style.css' => ['style.css', 'text/css; charset=utf-8'],
  '/script.js' => ['script.js', 'application/javascript; charset=utf-8']
}.freeze

def default_scenario_data
  JSON.parse(File.read(DEFAULT_SCENARIO_PATH))
end

def read_request(socket)
  request_line = socket.gets
  return nil if request_line.nil?

  method, path, = request_line.split(' ')
  headers = {}
  while (line = socket.gets) && line != "\r\n"
    name, value = line.split(':', 2)
    headers[name.strip.downcase] = value.strip if name && value
  end

  length = headers['content-length'].to_i
  body = length.positive? ? socket.read(length) : ''
  { method: method, path: path, headers: headers, body: body }
end

def write_response(socket, status, payload)
  body = JSON.generate(payload)
  socket.write("HTTP/1.1 #{status}\r\n")
  socket.write("Content-Type: application/json\r\n")
  socket.write("Content-Length: #{body.bytesize}\r\n")
  socket.write("Access-Control-Allow-Origin: *\r\n")
  socket.write("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n")
  socket.write("Access-Control-Allow-Headers: Content-Type\r\n")
  socket.write("Connection: close\r\n\r\n")
  socket.write(body)
end

def write_static(socket, status, body, content_type)
  socket.write("HTTP/1.1 #{status}\r\n")
  socket.write("Content-Type: #{content_type}\r\n")
  socket.write("Content-Length: #{body.bytesize}\r\n")
  socket.write("Connection: close\r\n\r\n")
  socket.write(body)
end

def write_no_content(socket)
  socket.write("HTTP/1.1 204 No Content\r\n")
  socket.write("Access-Control-Allow-Origin: *\r\n")
  socket.write("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n")
  socket.write("Access-Control-Allow-Headers: Content-Type\r\n")
  socket.write("Connection: close\r\n\r\n")
end

def handle_solve(body)
  raw = body.to_s.strip
  data = raw.empty? ? default_scenario_data : JSON.parse(raw)
  scenario = Scenario.new(data)
  UcsSolver.new(scenario).solve
rescue JSON::ParserError => e
  { status: '400 Bad Request', error: "Invalid JSON: #{e.message}" }
rescue ArgumentError => e
  { status: '400 Bad Request', error: e.message }
end

def route(request)
  method = request[:method]
  path = request[:path]

  return [:no_content, nil] if method == 'OPTIONS'
  return [:ok, { status: 'ok' }] if method == 'GET' && path == '/api/health'
  return [:ok, default_scenario_data] if method == 'GET' && path == '/api/scenario'

  if method == 'POST' && path == '/api/solve'
    result = handle_solve(request[:body])
    return [:ok, result] unless result.is_a?(Hash) && result[:status]

    kind = result[:status].start_with?('4') ? :client_error : :server_error
    return [kind, { error: result[:error] }]
  end

  if method == 'GET' && STATIC_FILES.key?(path)
    filename, content_type = STATIC_FILES.fetch(path)
    return [:static, [File.read(File.join(FRONTEND_DIR, filename)), content_type]]
  end

  [:not_found, { error: "Unknown route: #{method} #{path}" }]
end

STATUS_LINES = {
  ok: '200 OK',
  client_error: '400 Bad Request',
  server_error: '500 Internal Server Error',
  not_found: '404 Not Found'
}.freeze

def serve(socket)
  request = read_request(socket)
  return if request.nil?

  kind, payload = route(request)
  case kind
  when :no_content
    write_no_content(socket)
  when :static
    body, content_type = payload
    write_static(socket, '200 OK', body, content_type)
  else
    write_response(socket, STATUS_LINES.fetch(kind), payload)
  end
rescue StandardError => e
  write_response(socket, '500 Internal Server Error', { error: "Server error: #{e.message}" })
ensure
  socket.close
end

if __FILE__ == $PROGRAM_NAME
  port = (ARGV[0] || ENV.fetch('PORT', 3000)).to_i
  server = TCPServer.new(port)
  puts "Emergency Control solver listening on http://localhost:#{port}"
  puts 'Routes: GET /, GET /api/health, GET /api/scenario, POST /api/solve'

  trap('INT') { exit }

  loop do
    client = server.accept
    Thread.new(client) { |socket| serve(socket) }
  end
end
