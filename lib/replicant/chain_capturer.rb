
module Ava

  class ChainCapturer < BasicObject
    attr_reader :args

    def initialize
      @args = []
    end

    def clear
      @args.clear
    end

    def add_arg method, *args, **named
      @args << {method: method, args: args, named: named}
    end

    def arg_string
      arguments = []
      slice = false
      @args.each do |arg|
        if arg[:method] == :[]
          string = "[#{arg[:args].first}]"
          slice = true
        else
          string = arg[:method].to_s
        end
        if !arg[:args].empty? && (!slice || arg[:args].size > 1) || !arg[:named].empty?
          paren = '('
          if slice
            paren+= arg[:args][1..-1].map{ |a| a.to_s }.join(', ')
          else
            paren+= arg[:args].map{ |a| a.to_s }.join(', ')
          end
          paren+= ', ' if paren != '(' && !arg[:named].empty?
          paren+= arg[:named].map{ |k,v| "#{k}: #{v.is_a?(::String) ? "'#{v}'" : v}"}.join(', ')
          string+= paren + ')'
        end
        if slice
          arguments[-1]+= string
        else
          arguments << string
        end
      end
      arguments.join('.')
    end

    def method_missing sym, *args, **named
      add_arg(sym, *args, **named)
      self
    end

    def class
      ChainCapturer
    end

    def is_replicant?
      false
    end

  end

end
