module Ava

  class Client < BBLib::LazyClass

    attr_string :host, default: 'localhost'
    attr_string :key, allow_nil: true
    attr_bool :encrypt, default: true
    attr_int_between 0, nil, :port, default: 2016

    def inspect
      "#<#{self.class}:#{self.object_id}>"
    end


    def get_id key = @key
      @key = key if @key =! key
      @client_id[:encrypt] = false
      begin
        @client_id = request(secret_key: key)
        puts "CLIENT - #{@client_id}"
        true
      rescue StandardError => e
        puts "ERROR: #{e}; #{e.backtrace}"
        @client_id = { key: nil, iv: nil, encrypt: false }
        false
      end
    end

    def registry
      request(object: :controller, methods: [{ registry_list: [] }])
    end

    def required_gems
      request(:controller, :required_gems)
    end

    def missing_gems
      required_gems - Gem.loaded_specs.keys
    end

    def require_missing_gems
      missing_gems.map do |gem|
        begin
          require gem
          [gem, true]
        rescue Exception, StandardError => e
          [gem, false]
        end
      end.to_h
    end

    def method_missing *args
      if registry.any?{ |o| o.to_sym == args.first}
        object args.first
      else
        super
      end
    end

    def object name
      raise ArgumentError, "No object is registered under the name '#{name}'." unless registry.include?(name)
      Replicant.new name, self
    end

    # def object_send obj, *methods
    #   object(name).send()
    # end

    def request req
      begin
        connect
        @socket.puts encrypt(req.merge(client_id: @client_id[:key]).to_yaml)
        lines = Array.new
        while line = @socket.gets
          lines << line
        end
        @response = decrypt(YAML.load(lines.join))
          .map{ |k,v| [k.to_sym, v]}.to_h
      ensure
        close
      end
      puts "RESPONSE FROM CNTL - #{@response}"
      @response[:response] ? @response[:response] : (raise @response[:error].to_s)
    end

    protected

      def lazy_setup
        @client_id = { key: nil, iv: nil, encrypt: false }
      end

      def lazy_init *args
        get_id(@key) if @key
      end

      def connect
        @socket = TCPSocket.open(@host, @port)
      end

      def close
        @socket.close if defined?(@socket)
      end

      def encrypt msg
        return msg unless @client_id[:encrypt]
        cipher    = get_cipher(:encrypt)
        encrypted = cipher.update msg.to_yaml
        encrypted << cipher.final
        { encrypted: encrypted, client_id: @client_id[:key] }.to_yaml
      end

      def decrypt msg
        return msg unless @client_id[:encrypt] && msg.is_a?(Hash) && msg[:encrypted]
        cipher    = get_cipher(:decrypt)
        decrypted = cipher.update msg[:encrypted]
        decrypted << cipher.final
        YAML.load(YAML.load(decrypted))
      end

      def get_cipher type
        cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
        cipher.send(type)
        cipher.key = @client_id[:key]
        cipher.iv  = @client_id[:iv]
        return cipher
      end

  end

end
