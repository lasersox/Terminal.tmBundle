#!/usr/bin/ruby
# encoding: utf-8

require 'pty'
require 'net/http'

require ENV["TM_BUNDLE_SUPPORT"] + "/web_socket"
require ENV["TM_SUPPORT_PATH"] + "/lib/escape"


$KCODE = 'u' if RUBY_VERSION < "1.9"

$stdin.sync = true
$stderr.sync = true
$stdout.sync = true

module TextMate; module Terminal; class << self

  def parse_hashbang(str)
    $1.chomp if /\A#!(.*)$/ =~ str
  end

  def start_with(*args, &block)

    io_serv = WebSocketServer.new(:accepted_domains => ["*"], :port => 8080)
    port = io_serv.tcp_server.addr[1]

    Thread.abort_on_exception = true

    rd, wr = ::IO.pipe
    rd.sync = true
    wr.sync = true 

    Thread.new do
      io_serv.run do |ws|
        ws.handshake
        while data = ws.receive
          wr.write data
        end
      end
    end
    puts <<-HTML
    <html>
    <head>
      <script src='http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js'></script>
      <script type="text/javascript">
        var ws = new WebSocket("ws://localhost:#{port}");          
        ws.onerror = function() { alert(evt.data); }
        ws.onopen = function() {
          $(document).keypress(function(e) {
            event.preventDefault();
            ch = String.fromCharCode(e.charCode);
            //if (ch == '\\r') { ch = '\\n'; }
            ws.send(ch);
            return false;
          });
        }
      </script>
    </head>
    <body style="background: black; color: white;">
    <pre id="term">
    HTML
    wait(rd, *args, &block)
  end
  
  private
  def wait(io_rd, *args, &block)
    PTY.spawn(args.join(" ")) do |pty_rd, pty_wr, pid|
      pty_rd.sync = true
      pty_wr.sync = true

      Thread.new do
        begin
          while data = io_rd.readchar.chr
            pty_wr.write data
          end
        rescue IOError
        ensure
          io_rd.close
        end
      end

      begin
        while data = pty_rd.readchar.chr
          $stdout.write data
        end
      rescue EOFError
      end

      Process.wait pid
      $stdout.puts '[Process completed]'
    end

    exit
  end

end end end

if __FILE__ == $0
  TextMate::Terminal.start_with("read x; echo hello $x '\\n';")
end
