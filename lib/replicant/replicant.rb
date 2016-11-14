
# frozen_string_literal: true
module Ava
  class Replicant < BasicObject
    def initialize(object, client)
      @_object = object
      @_client = client
    end

    def replicant?
      true
    end

    def method_missing(method, *args)
      @_client.request(object: @_object, methods: [{ method => args }])
    end

    def to_chained_replicant(chain = [])
      ChainedReplicant.new @_object, @_client, [chain].flatten(1)
    end

    alias tcr to_chained_replicant
  end
end
