module Ava

  class Controller < BBLib::LazyClass
    attr_string :key, default: 'changeme'
    attr_int_between 0, nil, :port, default: 2016
    attr_bool :encrypt, :allow_deep_send, default: true
    attr_reader :registry, :blacklist, :whitelist, :connections, :error

    RESERVED_NAMES = [ :controller, :methods, :addresses ]

    def start
      listen unless @thread && @thread.alive?
      running?
    end

    def stop
      @thread.kill if @thread && @thread.alive?
      !running?
    end

    def restart
      stop && start
    end

    def running?
      @thread && @thread.alive?
    end

    def whitelist_method *methods, object: :methods
      @whitelist[object] = [] unless @whitelist[object]
      @whitelist[object] += methods
    end

    def blacklist_method *methods, object: :methods
      @blacklist[object] = [] unless @blacklist[object]
      @blacklist[object] += methods
    end

    def blacklist_all_methods object
      @blacklist[object] = [:_all]
    end

    def whitelist_address *patterns
      @whitelist[:addresses] += patterns
    end

    def blacklist_address *patterns
      @blacklist[:addresses] += patterns
    end

    def register objects
      objects.each do |name, object|
        raise "#{name} is a reserved object name. Please choose something else." if RESERVED_NAMES.include?(name.to_sym)
        @registry[name.to_sym] = object
      end
    end

    def registry_list
      @registry.keys
    end

    def remove name
      @registry.delete(name.to_sym)
    end

    def required_gems
      Gem.loaded_specs.keys
    end

    protected

      def lazy_setup
        @registry    = { controller: self }
        @blacklist   = { methods: [:eval], addresses: nil }
        @whitelist   = { methods: Array.new, addresses: nil }
        @cipher      = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
        @connections = Hash.new
        blacklist_all_methods(:controller)
        whitelist_method(
          :port,
          :restart,
          :running?,
          :registry_list,
          :required_gems,
          :encrypt,
          object: :controller
        )
      end

      def listen
        @thread = Thread.new{
          begin
            server = TCPServer.new(@port)
            loop do
              Thread.start(server.accept) do |client|
                begin
                  client.puts( handle_request(client) )
                rescue StandardError => e
                  client.puts( { status: 500, error: e }.to_yaml )
                ensure
                  client.close
                end
              end
            end
          rescue StandardError => e
            @error = e
          end
        }
      end

      def handle_request client
        remote_ip = client.peeraddr[3]
        msg = decrypt(remote_ip, YAML.load(client.recv(1000000000)))
        return msg.to_yaml if msg[:status] == 404
        if msg[:secret_key]
          response = { status: 202, response: register_client(remote_ip, msg[:secret_key]) }
        elsif validate_connection(remote_ip, msg)
          response = run_command(msg)
        else
          response = { status: 401, error: ArgumentError.new('Invalid or missing client ID.') }
        end
        encrypt(remote_ip, clean_payload(response.to_yaml), response)
      end

      def register_client addr, key
        return "Your IP is not allowed: #{addr}" unless validate_ip(addr)
        return { status: 401, error: ArgumentError.new("Invalid secret key.") } unless @key == key
        @connections[addr] = {
          key: Digest::SHA1.hexdigest("#{addr}|#{@key}"),
          iv: @cipher.random_iv,
          encrypt: @encrypt
        }
      end

      def validate_ip addr
        return true if @whitelist[:addresses].nil? && @blacklist[:addresses].nil?
        @whitelist[:addresses].any? do |ac|
          if ac.is_a?(String)
            addr == ac
          elsif ac.is_a?(Regexp)
            addr =~ ac
          end
        end
      end

      def validate_connection addr, msg
        return false unless msg.include?(:client_id)
        @connections.include?(addr) && @connections[addr][:key] == msg.delete(:client_id)
      end

      def validate_method object, method
        return true if @whitelist[:methods].include?(method) || @whitelist.include?(object) && @whitelist[object].include?(method)
        return false if @blacklist[:methods].include?(method) || @blacklist.include?(object) && (@blacklist[object].include?(method) || @blacklist[object].include?(:_all))
        return true
      end

      def encrypt addr, msg, response
        return msg if !@encrypt || response[:key] || response[:status] && [401, 202].any?{ |s| s == response[:status] }
        cipher = get_cipher(addr, :encrypt)
        encrypted   = cipher.update(msg.to_yaml)
        encrypted << cipher.final
        { encrypted: encrypted }.to_yaml
      end

      def decrypt addr, msg
        return msg unless @encrypt && msg.include?(:encrypted)
        return { status: 404, error: ArgumentError.new("Unregistered client. You must get a client_id first for #{addr}.") } unless @connections.include?(addr)
        cipher = get_cipher(addr, :decrypt)
        decrypted  = cipher.update msg[:encrypted]
        decrypted << cipher.final
        YAML.load( YAML.load(decrypted) )
      end

      def get_cipher addr, type
        cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
        cipher.send(type)
        cipher.key = @connections[addr][:key]
        cipher.iv  = @connections[addr][:iv]
        return cipher
      end

      def clean_payload msg
        ['!ruby/object:Thread', '!ruby/object:Proc']
          .each{ |w| msg.gsub!(w, '') }
        msg
      end

      def run_command msg
        begin
          object  = msg[:object]
          methods = msg[:methods]

          if @registry.include?(object)
            object = @registry[object]
            return { stauts: 200, response: object } unless methods
            methods.each do |mth|
              method = mth.keys.first
              args = mth.values.first
              return { status: 405, error: ArgumentError.new("You are not authorized to run '#{method}' on '#{object}'.") } unless validate_method(object, method)
              object = object.send(method, *args)
            end
            return { status: 200, response: object }
          else
            return { status: 404, error: ArgumentError.new("No objected named '#{object}' found in registry.") }
          end
        rescue StandardError => e
          return { status: 500, error: e }
        end
      end

  end

end
