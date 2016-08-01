

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
        raise ::ArgumentError, "To set a chain, it must be either an array of hashes that must contain a :method key/value"
      end
    end

    def method_missing method, *args, **named
      build = @chain + [{method: method, args: args, named: named}]
      ChainedReplicant.new(@object, @client, build)
    end

    def _self
      if @chain && !@chain.empty?
        @client.deep_send @chain, @object
      else
        @client.get_object(object)
      end
    end

    alias_method :_send, :_self

  end

end
