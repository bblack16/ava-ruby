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
        raise 'Error retrieving client_id from host: ' + response.to_s
      end
    end

    def object_list
      request(:controller, :object_list)
    end

    def method_missing *args, **named
      if args.size == 1 && (named == {} || named.nil?) && object_list.any?{ |o| o.to_sym == args.first}
        Replicant.new args.first, self
      else
        request args.first, args[1], *args[2..-1], **named
      end
    end

    def request object, method, *args, **named
      connect
      argument = (named.nil? ? {} : named).merge({args:args})
      request = {object => { method => argument }, client_id: @client_id[:key] }
      @socket.puts encrypt_msg(request.to_yaml)
      lines = Array.new
      while line = @socket.gets
        lines << line
      end
      @response = decrypt_msg(YAML.load(lines.join)).map{ |k,v| [k.to_sym, v]}.to_h
      close
      @response[:response] ? @response[:response] : (raise @response[:error])
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
