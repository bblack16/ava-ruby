module Ava

  class Controller
    attr_reader :objects, :blacklist, :whitelist, :key, :port, :thread, :connections,
                :allowed_connections, :encrypt

    def initialize *args, **named
      @objects, @connections = {}, {}
      @whitelist, @blacklist = {methods:[]}, {methods:[:eval]}
      @allowed_connections = nil
      setup_defaults
      self.key = named.include?(:key) ? named[:key] : SecureRandom.hex(20)
      self.port = named.include?(:port) ? named[:port] : 2016
      self.encrypt = named.include?(:encrypt) ? named[:encrypt] : true
      listen if named.include?(:start) && named[:start]
    end

    def encrypt= e
      @encrypt = e == true
    end

    def key= key
      @key = key.to_s
    end

    def port= port
      @port = BBLib::keep_between(port, 1, nil)
    end

    def start
      listen unless defined?(@thread) && @thread.alive?
      running?
    end

    def stop
      @thread.kill if defined?(@thread) && @thread.alive?
      !running?
    end

    def restart
      stop && start
    end

    def running?
      defined?(@thread) && @thread.alive?
    end

    def register **objects
      objects.each do |name, object|
        name = name.to_sym
        raise "Cannot name an object :controller, it is reserved." if name == :controller
        @objects[name] = object
      end
    end

    def allow_connections *connections
      @allowed_connections = connections.first.nil? ? nil : connections
    end

    def remove name
      @objects.delete name unless name == :controller
    end

    def whitelist name, *methods
      name = name.to_sym
      raise ArgumentError, "You cannot whitelist methods for :controller." if name == :controller
      if @whitelist.include?(name)
        (@whitelist[name]+=methods).uniq!
      else
        @whitelist[name] = methods
      end
    end

    def whitelist_method *methods
      @whitelist[:methods]+=methods
    end

    def blacklist name, *methods
      if @blacklist.include?(name)
        (@blacklist[name]+=methods).uniq!
      else
        @blacklist[name] = methods
      end
    end

    def blacklist_all object
      blacklist object, :_all
    end

    def blacklist_global *methods
      @blacklist[:methods]+=methods
    end

    def registered_objects
      @objects.keys
    end

    def required_gems
      Gem.loaded_specs.keys
    end

    def parse_command cmd
      begin
        object = cmd.keys.first
        method = cmd[object].keys.first
        args = cmd[object][method].delete :args
        named = cmd[object][method]
        run_method(object, method, *args, **named)
      rescue StandardError, Exception => e
        {status: 500, error: "#{e}\n#{e.backtrace.join("\n")}"}
      end
    end

    def run_method object, method, *args, **named
      if @objects.include?(object)
        return {status: 401, error: "You are not authorized to run '#{method}' on '#{object}'."} unless validate_method(object, method)
        obj = @objects[object]

        a = !args.nil? && (!args.is_a?(Array) || !args.empty?)
        n = !named.nil? && !named.empty?
        begin
          if a && n
            res = obj.send(method, *args, **named)
          elsif !a && n
            res = obj.send(method, **named)
          elsif a && !n
            res = obj.send(method, *args)
          else
            res = obj.send(method)
          end
          {status: 200, response: res}
        rescue StandardError, Exception => e
          {status: 501, error: "#{e}\n#{e.backtrace.join("\n")}"}
        end
      else
        {status: 404, error: "Object '#{object}' does not exist."}
      end
    end

    protected

      def validate_method object, method
        return true if @whitelist[:methods].include?(method) || @whitelist.include?(object) && @whitelist[object].include?(method)
        return false if @blacklist[:methods].include?(method) || @blacklist.include?(object) && (@blacklist[object].include?(method) || @blacklist[object].include?(:_all))
        return true
      end

      def listen
        @thread = Thread.new {
          begin
            server = TCPServer.new(@port)
            loop do
              Thread.start(server.accept) do |client|
                sock_domain, remote_port, remote_hostname, remote_ip = client.peeraddr
                begin
                  encrypt = true
                  msg = decrypt_msg(remote_ip, YAML.load(client.recv(100000)))
                  if msg[:controller] && msg[:controller][:secret_key]
                    if msg[:controller][:secret_key][:args].first == @key
                      response = {status:200, response: register_client(remote_ip)}
                      encrypt = false
                    else
                      response = {status:401, error: ArgumentError.new('Invalid secret key.')}
                      encrypt = false
                    end
                  elsif verify_connection(remote_ip, msg)
                    response =  parse_command(msg)
                  else
                    response = {status: 401, error: ArgumentError.new("Invalid or missing client ID.")}
                    encrypt = false
                  end
                rescue StandardError, Exception => e
                  response = {status: 501, error: "#{e}\n#{e.backtrace.join}"}
                  encrypt = false
                end
                response.hash_path_set 'time' => Time.now
                client.puts(encrypt ? encrypt_msg(remote_ip, response.to_yaml) : response.to_yaml)
                client.close
              end
            end
          rescue StandardError, Exception => e
            e
          end
        }
      end

      def register_client addr
        return "Your IP is not allowed: #{addr}" unless validate_ip(addr)
        client_id = Digest::SHA1.hexdigest("#{addr}|#{@key}")
        iv = @cipher.random_iv
        @connections[addr] = {key: client_id, iv: iv, encrypt: @encrypt}
      end

      def validate_ip addr
        return true if @allowed_connections.nil?
        match = false
        [@allowed_connections].flatten.each do |format|
          if String === format
            match = true if addr == format
          elsif Regexp === format
            match = true if addr =~ format
          end
        end
        match
      end

      def verify_connection ip, msg
        return false unless msg.include?(:client_id)
        @connections.include?(ip) && @connections[ip][:key] == msg.delete(:client_id)
      end

      def setup_defaults
        @objects[:controller] = self
        blacklist_all :controller
        @whitelist[:controller] = [
          :port,
          :restart,
          :running?,
          :registered_objects,
          :required_gems
        ]
        @cipher = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
      end

      def encrypt_msg addr, msg
        return msg if !@encrypt
        cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
        cipher.encrypt
        cipher.key = @connections[addr][:key]
        cipher.iv = @connections[addr][:iv]
        enc = cipher.update msg.to_yaml
        enc << cipher.final
        {encrypted: enc}.to_yaml
      end

      def decrypt_msg addr, msg
        return msg if !@encrypt || !msg.include?(:encrypted)
        raise ArgumentError, "Unregistered client. You must get a client_id first for #{addr}" unless @connections.include?(addr)
        cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
        cipher.decrypt
        cipher.key = @connections[addr][:key]
        cipher.iv = @connections[addr][:iv]
        dec = cipher.update msg[:encrypted]
        dec << cipher.final
        YAML.load(YAML.load(dec))
      end
  end

end
