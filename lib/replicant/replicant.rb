
module Ava

  class Replicant < BasicObject
    attr_accessor :object, :client

    def initialize object, client
      self.object = object
      self.client = client
    end

    def is_replicant?
      true
    end

    def method_missing method, *args, **named
      @client.request @object, method, *args, **named
    end

    def to_chained_replicant chain = []
      ChainedReplicant.new @object, @client, [chain].flatten(1)
    end

    alias_method :tcr, :to_chained_replicant

    def _get chain
      to_chained_replicant(chain)
    end

  end

end

class Object

  def is_replicant?
    false
  end

end
