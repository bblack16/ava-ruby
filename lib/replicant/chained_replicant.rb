

module Ava

  class ChainedReplicant < Replicant
    attr_reader :chain

    def initialize object, client, chain
      @object = object
      @client = client
      self.chain = chain
    end

    def chain= chain
      if chain.is_a?(::Array) && chain.all?{ |v| v.is_a?(::Hash) && v.include?(:method) }
        @chain = chain
      else
        raise ArgumentError, "To set a chain, it must be either an array of hashes that must contain a :method key/value"
      end
    end

    def method_missing method, *args, **named
      @client.set_chain :replicant, @chain.dup + [{method: method, args: args, named: named}]
      @client.send_chain :replicant, @object
    end

    def get_self
      @client.set_chain :replicant, @chain
      @client.send_chain :replicant, @object
    end

    def get method, *args, **named
      ChainedReplicant.new(@object, @client, @chain.dup + [{method: method, args: args, named: named}])
    end

  end

end
