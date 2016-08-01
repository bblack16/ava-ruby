class Object

  def chain_send(*chain)
    current = chain.first
    args = [current[:method]] +
            (current[:args] || []) +
            (current[:named].nil? || current[:named].empty? ? [] : current[:named])
    result = send(*args)
    return result if chain.size <= 1
    result.chain_send(*chain[1..-1])
  end

end
