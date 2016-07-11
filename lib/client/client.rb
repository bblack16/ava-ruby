module Ava

  class Client
    attr_accessor :host, :port, :socket, :response, :chains, :save_key, :raw_mode

    def initialize host: 'localhost', port: 2016, key: nil, save_key: true, raw_mode: false
      self.host = host
      self.port = port
      self.save_key = true
      self.raw_mode = raw_mode
      @client_id = {key: nil, iv: nil, encrypt: false}
      @chains = Hash.new
      get_id(key) if key
    end

    def inspect
      "#<#{self.class}:#{self.object_id}>"
    end

    def connect
      @socket = TCPSocket.open(@host, @port)
    end

    def close
      @socket.close if defined?(@socket)
    end

    def get_id key = @key
      @key = key if @save_key
      @client_id[:encrypt] = false
      begin
        @client_id = request :controller, :secret_key, key
        true
      rescue
        @client_id = {key: nil, iv: nil, encrypt: false}
        false
      end
    end

    def get_object name
      raise ArgumentError, "No object is registered under the name '#{name}'." unless registered_objects.include?(name)
      Replicant.new name, self
    end

    def registered_objects
      request(:controller, :registered_objects)
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

    def method_missing *args, **named
      if args.size == 1 && (named == {} || named.nil?) && registered_objects.any?{ |o| o.to_sym == args.first}
        get_object args.first
      else
        request args.first, args[1], *args[2..-1], **named
      end
    end

    def request object, method = nil, *args, **named
      return get_object(object) if method.nil?
      connect

      raw       = named.delete(:raw) || @raw_mode
      rtry      = named.include?(:retry) ? named.delete(:retry) : true
      argument  = (named.nil? ? {} : named).merge({args:args})
      request   = {object => { method => argument }, client_id: @client_id[:key], raw: raw }

      @socket.puts encrypt_msg(request.to_yaml)
      lines = Array.new
      while line = @socket.gets
        lines << line
      end

      @response = decrypt_msg(YAML.load(lines.join)).map{ |k,v| [k.to_sym, v]}.to_h
      close

      if rtry && @response[:status] == 401 && @save_key && @key
        if get_id
          return request(object, method, *args, **named.merge(retry: false))
        else
          raise 'Failed to reauthenticate with the current saved key. Please call get_id with a valid key'
        end
      end

      @response[:response] ? @response[:response] : (raise @response[:error].to_s)
    end

    def deep_send chain, object
      request :controller, :deep_send, chain: chain, object: object
    end

    def deep_send?
      request :controller, :allow_deep_send
    end

    def send_file bits, save_to = ''
      request :send_file, :send_file, bits, path: save_to
    end

    def get_file path, save_to = Dir.pwd
      save_to+= path.file_name if File.directory?(save_to)
      File.open(save_to, 'w') do |file|
        file.write(read_file(path))
      end
      File.exists?(save_to)
    end

    def read_file path
      request :get_file, :get_file, path: path
    end

    def encrypt_msg msg
      return msg if !@client_id[:encrypt]
      cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = @client_id[:key]
      cipher.iv = @client_id[:iv]
      enc = cipher.update msg.to_yaml
      enc << cipher.final
      {encrypted: enc, client_id: @client_id[:key]}.to_yaml
    end

    def decrypt_msg msg
      return msg if !@client_id[:encrypt] || !msg.is_a?(Hash) ||!msg.include?(:encrypted)
      cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = @client_id[:key]
      cipher.iv = @client_id[:iv]
      dec = cipher.update msg[:encrypted]
      dec << cipher.final
      YAML.load(YAML.load(dec))
    end

  end

end
