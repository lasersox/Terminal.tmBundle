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

    io_serv = WebSocketServer.new(:accepted_domains => ["*"], :port => 0)
    port = io_serv.tcp_server.addr[1]

    $stderr.write("serving on port #{port}")
    
    if $stdout.tty?
      wait(io_serv, *args, &block)
    else
      pid = fork do

        $stdin.reopen("/dev/null")
        $stdout.reopen("/dev/null")
        $stderr.reopen("/dev/null")

        wait(io_serv, *args, &block)

      end
      Process.detach(pid)
    end

    puts <<-HTML

    <html>
    <head>
      <script src='http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js'></script>
      <script src='file://#{e_url(ENV["TM_BUNDLE_SUPPORT"])}/vt100.js'></script>
      <script type="text/javascript">

        var ws;
        var vt;
        $(document).ready(function() {

          vt = new VT100(80,30,'term');
          vt.noecho();

          ws = new WebSocket("ws://localhost:#{port}");          

          getcha_ = function(ch, vt){
            ws.send(ch);
            vt.getch(getcha_);
          };

          ws.onmessage = function(evt) {
            vt.write(evt.data);
            return false;
          };

          ws.onclose = function() { vt.curs_set(0, false); };
          ws.onopen = function() { vt.curs_set(1, true); };
        });
      </script>
    </head>
    <body style="background: black;">
    <pre id="term">
    </pre>
    </body>
    </html>
    HTML
  end
  
  private
  def wait(io_serv, *args, &block)
    Thread.abort_on_exception = true
    io_serv.run do |ws|

      at_exit { exit! }
      ws.handshake

      rd, wr = ::IO.pipe
      wr.sync = true
      rd.sync = true

      Thread.new do
        begin
          puts 'reading'
          while byte = ws.receive
            next if byte == '\r'
            wr.write byte
          end
        rescue IOError         
        ensure
          wr.close
        end
      end

      ENV['TM_PTY_ARGS'] = args.join(" ")
      PTY.spawn(args.join(" ")) do |proc_rd, proc_wr, pid|
        
        Thread.new do
          while byte = rd.readchar.chr
            proc_wr.write byte
          end
        end
        
        begin
          while byte = proc_rd.readchar.chr do
            ws.send(byte)
          end
        rescue EOFError
        ensure
          ws.close
        end
        
      end
      exit
    end
  end

end end end

if __FILE__ == $0
  TextMate::Terminal.start_with("/usr/bin/zsh")
end
