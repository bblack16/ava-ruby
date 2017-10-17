# frozen_string_literal: true
module Ava
  class Client
    include BBLib::Effortless

    attr_string :host, default: 'localhost'
    attr_string :key, allow_nil: true
    attr_bool :encrypt, :sanitize_yaml, default: true
    attr_bool :chain_mode, :registered, default: false
    attr_int_between 0, nil, :port, default: 2016
    # Private
    attr_hash :client_id, private: true, default: { key: nil, iv: nil, encrypt: false }

    def inspect
      "#<#{self.class}:#{object_id}>"
    end

    def register(key = self.key)
      self.key = key if self.key != key
      client_id[:encrypt] = false
      begin
        self.client_id = request(secret_key: key)
        self.registered = true
      rescue StandardError => _e
        self.client_id = { key: nil, iv: nil, encrypt: false }
        false
      end
    end

    def registry
      request(object: :controller, methods: [{ registry_list: [] }])
    end

    def required_gems
      request(object: :controller, methods: [{ required_gems: [] }])
    end

    def missing_gems
      required_gems - Gem.loaded_specs.keys
    end

    def require_missing_gems
      missing_gems.map do |gem|
        begin
          require gem
          [gem, true]
        rescue => _e
          [gem, false]
        end
      end.to_h
    end

    def method_missing(*args)
      if registry.any? { |o| o.to_sym == args.first }
        object args.first
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      registered && registry.any? { |o| o.to_sym == method } || super
    end

    def object(name)
      raise ArgumentError, "No object is registered under the name '#{name}'." unless registry.include?(name)
      !chain_mode ? Replicant.new(name, self) : Replicant.new(name, self).tcr
    end

    def request(req, rtry: true)
      begin
        connect
        @socket.puts encrypt(req.merge(client_id: client_id[:key]).to_yaml)
        lines = []
        while line = @socket.gets
          lines << line
        end
        msg = YAML.load(lines.join)
        @response = decrypt(msg).map { |k, v| [k.to_sym, v] }.to_h
      ensure
        close
      end
      if rtry && (msg[:status] == 404 || msg[:status] == 401) # If authentication fails, try once more
        return request(req, rtry: false) if register
      end
      @response[:response] ? @response[:response] : (raise @response[:error].to_s)
    end

    protected

    def simple_init(*_args)
      register(key) if key
    end

    def connect
      @socket = TCPSocket.open(host, port)
    end

    def close
      @socket.close if defined?(@socket)
    end

    def encrypt(msg)
      return msg unless client_id[:encrypt]
      cipher    = get_cipher(:encrypt)
      encrypted = cipher.update msg.to_yaml
      encrypted << cipher.final
      { encrypted: encrypted, client_id: @client_id[:key] }.to_yaml
    end

    def decrypt(msg)
      return msg unless client_id[:encrypt] && msg.is_a?(Hash) && msg[:encrypted]
      cipher    = get_cipher(:decrypt)
      decrypted = cipher.update msg[:encrypted]
      decrypted << cipher.final
      YAML.load(sanitize_yaml(YAML.load(sanitize_yaml(decrypted))))
    end

    def get_cipher(type)
      cipher = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
      cipher.send(type)
      cipher.key = client_id[:key]
      cipher.iv  = client_id[:iv]
      cipher
    end

    # This method goes through and removes any classes that are missing.
    # This prevents psych from being unable to parse the response if it
    # includes ruby objects.
    # Somewhat experimental, but works in most cases so far
    def sanitize_yaml(msg)
      return msg unless sanitize_yaml
      msg.scan(/\!ruby\/object\:.*/).uniq.each do |obj|
        klass = obj.sub('!ruby/object:', '').strip.chomp
        unless (Object.const_get(klass) rescue false)
          msg = msg.gsub(/#{obj}.*/, '')
        end
      end
      msg
    end
  end
end
