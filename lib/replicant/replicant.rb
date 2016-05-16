
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

  end

end

class Object

  def is_replicant?
    false
  end

end
