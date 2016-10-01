
module Ava

  class Replicant < BasicObject
    attr_accessor :_object, :_client

    def initialize object, client
      self._object = object
      self._client = client
    end

    def is_replicant?
      true
    end

    def method_missing method, *args
      @_client.request(object: @_object, method => args)
    end

    def to_chained_replicant chain = []
      ChainedReplicant.new @_object, @_client, [chain].flatten(1)
    end

    alias_method :tcr, :to_chained_replicant

  end

end
