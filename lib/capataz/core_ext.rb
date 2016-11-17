class BasicObject
  def capataz_proxy?
    false
  end

  def capataz_slave
    self
  end
end

module Parser
  module Source
    class Range

      def eql?(obj)
        self == obj
      end

      def hash
        begin_pos + 83 * end_pos
      end
    end
  end
end