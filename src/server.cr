require "./config"

class RubberSoul::Server

  def self.start(host, port, cluster = false, process_count = 1)
    # Load routes
    server = ActionController::Server.new(port: port, host: host)

    # Start clustering
    server.cluster(process_count, "-w", "--workers") if cluster

    terminate = Proc(Signal, Nil).new do |signal|
      puts " > terminating gracefully"
      spawn { server.close }
      signal.ignore
    end

    # Detect ctr-c to shutdown gracefully
    Signal::INT.trap &terminate
    # Docker containers use the term signal
    Signal::TERM.trap &terminate

    # Start the server
    server.run do
      puts "Listening on #{server.print_addresses}"
    end
  end

end
