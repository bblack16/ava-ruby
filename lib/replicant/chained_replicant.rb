

module Ava

  class ChainedReplicant < Replicant
    attr_reader :_chain

    def initialize object, client, chain
      @_object = object
      @_client = client
      @_chain = chain
    end

    def method_missing method, *args
      build = @_chain + [{method => args}]
      ChainedReplicant.new(@_object, @_client, build)
    end

    def _self
      if @_chain && !@_chain.empty?
        @_client.request(object: @_object, methods: @_chain)
      else
        @_client.object(@_object)
      end
    end

    alias_method :_send, :_self
    alias_method :_s, :_self

  end

end
