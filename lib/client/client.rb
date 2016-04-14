require_relative  'replicant'

module Ava

  class Client
    attr_accessor :host, :port, :socket, :response

    def initialize host: 'localhost', port: 2016, key: nil
      self.host = host
      self.port = port
      @client_id = {key: nil, iv: nil, encrypt: false}
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

    def get_id key
      @client_id[:encrypt] = false
      response = request :controller, :secret_key, key
      if response
        @client_id = response
        true
      else
        false
      end
    end
    
    def get_object name
      Replicant.new name, self if registered_objects.include?(name)
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
        rescue
          [gem, false]
        end
      end.to_h
    end

    def method_missing *args, **named
      if args.size == 1 && (named == {} || named.nil?) && registered_objects.any?{ |o| o.to_sym == args.first}
        Replicant.new args.first, self
      else
        request args.first, args[1], *args[2..-1], **named
      end
    end

    def request object, method = nil, *args, **named
      return get_object(object) if method.nil?
      connect
      raw = named.delete(:raw)
      argument = (named.nil? ? {} : named).merge({args:args})
      request = {object => { method => argument }, client_id: @client_id[:key], raw: raw }
      @socket.puts encrypt_msg(request.to_yaml)
      lines = Array.new
      while line = @socket.gets
        lines << line
      end
      @response = decrypt_msg(YAML.load(lines.join)).map{ |k,v| [k.to_sym, v]}.to_h
      close
      @response[:response] ? @response[:response] : (raise @response[:error])
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
      return msg if !@client_id[:encrypt] || !msg.include?(:encrypted)
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
