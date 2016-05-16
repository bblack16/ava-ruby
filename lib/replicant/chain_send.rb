class Object

  def chain_send(*chain)
    current = chain.first
    # p '1', current, '2',chain
    if current[:args].empty? && current[:named].empty?
      result = send(current[:method].to_sym)
    elsif !current[:args].empty? && !current[:named].empty?
      result = send(current[:method], *current[:args], **current[:named])
    elsif !current[:args].empty? && current[:named].empty?
      result = send(current[:method], *current[:args])
    else
      result = send(current[:method], **current[:named])
    end
    return result if chain.size <= 1
    result.chain_send(*chain[1..-1])
  end

end
