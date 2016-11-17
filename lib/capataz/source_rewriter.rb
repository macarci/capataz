
module Capataz

  class SourceRewriter < Parser::Source::Rewriter

    def preprocess
      hash = {}
      @queue.each do |action|
        if a = hash[action.range]
          hash[action.range] = Parser::Source::Rewriter::Action.new(a.range, action.replacement + a.replacement)
        else
          hash[action.range] = action
        end
      end
      @queue = hash.values.to_a
    end
  end
end