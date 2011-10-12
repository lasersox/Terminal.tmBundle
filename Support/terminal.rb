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

  def start_with(*args, &block)

    io_serv = WebSocketServer.new(:accepted_domains => ["*"], :port => 8081)
    port = io_serv.tcp_server.addr[1]
    puts "Serving on port #{port}..."

    if ENV.has_key?('TM_FILE_IS_UNTITLED')
      `cp "$TM_FILEPATH" "${TM_FILEPATH}.x"`
      ENV["TM_FILEPATH"] = ENV["TM_FILEPATH"] + ".x"
    end

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
      <script src='file://#{e_url(ENV["TM_BUNDLE_SUPPORT"])}/ovt100.js'></script>
      <script type="text/javascript">

        var ws;
        var vt;
        $(document).ready(function() {

          ws = new WebSocket("ws://localhost:#{port}");          
          vt = new VT100(80,30,'term');

          getcha_ = function(ch, vt){
            ws.send(ch);
            vt.getch(getcha_);
          };

          vt.getch(getcha_);

          ws.onmessage = function(evt) {
            vt.write(evt.data);
            return false;
          };

          vt.noecho();
          vt.curs_set(1, true);

          // ws.onclose = function() {
          //   $('#stdout').append("\\n\\nDONE\\n")
          // };
          // ws.onopen = function() { $('#stdout').append("\\nCONNECTED\\n") };
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