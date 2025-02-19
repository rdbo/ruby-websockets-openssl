# frozen_string_literal: true
require 'websocket'
require 'socket'
require 'openssl'
require 'net/http'

def open_secure_socket(host, port)
  tcp_socket = TCPSocket.new host, port
  context = OpenSSL::SSL::SSLContext.new
  context.verify_mode = OpenSSL::SSL::VERIFY_PEER
  context.min_version = :TLS1_2
  context.cert_store = OpenSSL::X509::Store.new
  context.cert_store.set_default_paths
  ssl_client = OpenSSL::SSL::SSLSocket.new tcp_socket, context
  ssl_client.hostname = host
  ssl_client.sync_close = false
  ssl_client.connect
  ssl_client
end

def read_http_response(sock, headers_only: false)
  payload = ""
  loop do
    begin
      result = sock.read_nonblock 4096
      payload += result
      break if headers_only && payload.include?("\r\n\r\n")
    rescue IO::WaitReadable
      IO.select([sock])
      retry
    rescue IO::WaitWritable
      IO.select(nil, [sock])
      retry
    rescue OpenSSL::SSL::SSLError, EOFError => e
      puts "Done reading with exception: #{e}"
      break
    rescue => e
      puts "Unhandled exception caught: #{e}"
      raise e
    end
  end

  payload
end

def open_websocket(uri, secure: true, headers: {})
  puts "Opening websocket..."
  sock =
    if secure
      open_secure_socket(uri.hostname, uri.port)
    else
      tcp_socket = TCPSocket.new uri.hostname, uri.port
      tcp_socket
    end

  puts "Sending websocket handshake..."
  handshake = WebSocket::Handshake::Client.new(url: uri.to_s, headers: headers)
  puts "Handshake: #{handshake}"
  sock.write handshake.to_s

  puts "Receiving server response..."
  resp = read_http_response sock, headers_only: true

  puts "Server response: #{resp}"

  [sock, handshake]
end

sock, handshake = open_websocket URI("ws://127.0.0.1:8080/"), :secure => false

loop do
  puts "Sending message to the server..."
  sock.write WebSocket::Frame::Outgoing::Client.new(version: handshake.version, data: 'Hello, server!', type: :text)
  puts "Waiting for response..."
  begin
    buf = sock.read_nonblock 4096
    puts "Message from the server: #{buf}"
  rescue IO::WaitReadable
    IO.select([sock])
    retry
  rescue IO::WaitWritable
    IO.select(nil, [sock])
    retry
  rescue => e
    puts "Unhandled exception caught: #{e}"
    raise e
  end
end
