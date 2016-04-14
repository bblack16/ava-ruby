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

    def method_missing *args, **named
      @client.request @object, args.first, *args[1..-1], **named
    end

  end

end
