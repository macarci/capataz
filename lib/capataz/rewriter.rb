require 'capataz/source_rewriter'

module Capataz

  class Rewriter < Parser::Rewriter

    attr_reader :logs

    def initialize(options = {})
      @options = options || {}
      @logs = options[:logs] || {}
      @self_linker = options[:self_linker]
      @self_send_prefixer = options[:self_send_prefixer]

      @max_instructions_allowed = 100
      @instruction_counter = 0
      @block_iter_counter = 0

      @capatized_nodes = Set.new
    end

    def rewrite(source_buffer, ast)
      @source_buffer = source_buffer

      @logs.clear
      @capatized_nodes.clear
      @source_rewriter = Capataz::SourceRewriter.new(source_buffer)

      process(ast)

      if @instruction_counter > @max_instructions_allowed
        report_error('number of allowed instructions exceeded')
      end

      @source_rewriter.preprocess

      new_source = @source_rewriter.process
      @block_iter_counter.downto(1) do |i|
        new_source = "block_iter_counter_#{i} = 0\n#{new_source}"
      end

      new_source

    end

    def on_array(node)
      @instruction_counter += 1
      super
      node.children.each { |child| decapatize(child) }
    end

    def on_block(node)

      first_range = Parser::Source::Range.new(@source_buffer, node.location.begin.begin_pos, node.location.begin.end_pos)
      replace(first_range, "{")
      second_range = Parser::Source::Range.new(@source_buffer, node.location.end.begin_pos, node.location.end.end_pos)
      replace(second_range, "}")

      if node.children[1].children.length > 0
        insert_after(node.children[1].location.end, "\n#{inc_block_iter_counter}")
      else
        insert_after(node.location.begin, "\n#{inc_block_iter_counter}")
      end

      super
    end

    def on_for(node)

      insert_after(node.children[1].location.end, "\n#{inc_block_iter_counter}")
      super

    end

    def on_kwbegin(node)

      insert_after(node.location.begin, "\n#{inc_block_iter_counter}")
      super
    end

    def on_while(node)

      insert_after(node.children[0].location.expression, "\n#{inc_block_iter_counter}")
      super
    end

    def on_while_post(node)

      #insert_after(node.children[1].location.end, "\n#{inc_block_iter_counter}")
      super
    end

    def on_until(node)

      insert_after(node.children[0].location.expression, "\n#{inc_block_iter_counter}")
      super
    end

    def on_until_post(node)

      #insert_after(node.children[1].location.begin, "\n#{inc_block_iter_counter}")
      super

    end

    def on_send(node)
      #@instruction_counter += 1


      super
      method_name = node.children[1]
      unless Capataz.allows_invocation_of(method_name)
        report_error("invoking method '#{method_name}' is not allowed")
      end
      if (left = node.children[0])
        capatize(left)
      elsif node.type == :send
        unless @self_linker.link?(method_name)
          report_error("error linking #{method_name}")
        end if @self_linker
        (@logs[:self_sends] ||= Set.new) << method_name
        prefix = @self_send_prefixer ? @self_send_prefixer.prefix(method_name, @self_linker) : ''
        insert_before(node.location.expression, "::Capataz.handle(self).#{prefix}")
      end



      len = node.children.length
      if len > 2
        if node.children[len - 1].type == :block_pass or ((node.children[1] == :inject or node.children[1] == :reduce) and node.children[len - 1].type == :sym)
          rewrite_block_symbol_pass(node, len)
        end
      end

      i = 2
      while i < node.children.length
        decapatize(node.children[i])
        i += 1
      end
    end

    def on_return(node)
      report_error('can not use return') unless Capataz.can_declare?(:return)
      super
      capatize(node.children[2])
    end

    def on_casgn(node)
      report_error('can not define (or override) constants') unless Capataz.can_declare?(:constant)
      super
      capatize(node.children[2])
    end

    def on_lvasgn(node)
      @instruction_counter += 1
      super
      capatize(node.children[1])
    end

    def on_class(node)
      report_error('can not define classes') unless Capataz.can_declare?(:class)
      super
    end

    def on_module(node)
      report_error('can not define modules') unless Capataz.can_declare?(:module)
      super
    end

    def on_def(node)
      report_error('can not define methods') unless Capataz.can_declare?(:def)
      super
      insert_before(node.location.expression, ";::Capataz.denied_override_of(self, :#{node.children[0]});") unless Capataz.allow_method_overrides
    end

    def on_self(_)
      report_error('can not access to self') unless Capataz.can_declare?(:self)
    end

    def on_yield(node)
      report_error('can not make yield calls') unless Capataz.can_declare?(:yield)
      super
    end

    def on_ivasgn(_)
      report_error('can not access instance variables') unless Capataz.can_declare?(:ivar)
      super
    end


    def on_ivar(_)
      report_error('can not access instance variables') unless Capataz.can_declare?(:ivar)
      super
    end

    def on_cvasgn(_)
      report_error('can not access class variables') unless Capataz.can_declare?(:cvar)
      super
    end

    def on_cvar(_)
      report_error('can not access class variables') unless Capataz.can_declare?(:cvar)
      super
    end

    def on_gvar(_)
      report_error('can not access global variables') unless Capataz.can_declare?(:gvar)
      super
    end

    def on_gvasgn(_)
      report_error('can not access global variables') unless Capataz.can_declare?(:gvar)
      super
    end

    private

    def report_error(message)
      if @options[:halt_on_error]
        fail message
      else
        (logs[:errors] ||= []) << message
      end
    end

    def capatize(node, options = {})
      if node && !@capatized_nodes.include?(node)
        @capatized_nodes << node
        options[:constant] = true if node.type == :const
        @source_rewriter.insert_before_multi(node.location.expression, '::Capataz.handle(')
        if !options.empty?
          @source_rewriter.insert_after_multi(node.location.expression, ",
 #{options.to_a.collect { |item| "#{item[0]}: #{item[1]}" }.join(',')})")
        else
          @source_rewriter.insert_after_multi(node.location.expression, ')')
        end
      end
    end

    def decapatize(node)
      unless node.type == :hash or @decapatized_nodes.include?(node)
        begin
          @source_rewriter.insert_before_multi(node.children[0].location.expression, '(')
          @source_rewriter.insert_after_multi(node.children[0].location.expression, ').capataz_slave')
        rescue
          @source_rewriter.insert_before_multi(node.location.expression, '(')
          @source_rewriter.insert_after_multi(node.location.expression, ').capataz_slave')
        end
      end

      # ORIGINAL CODE
      # unless node.type == :hash or @decapatized_nodes.include?(node)
      #     @source_rewriter.insert_before_multi(node.location.expression, '(')
      #     @source_rewriter.insert_after_multi(node.location.expression, ').capataz_slave')
      # end
    end

    def const_from(node)
      if node
        const_from(node.children[0]) + '::' + node.children[1].to_s
      else
        ''
      end
    end

    def inc_block_iter_counter

      if Capataz.max_allowed_iterations == :inf
        return ""
      end

      @block_iter_counter += 1
      bc = @block_iter_counter
      "block_iter_counter_#{bc} += 1\nfail\
      \"ERROR: Maximum allowed iterations exceeded\" \
      if block_iter_counter_#{bc} \
      > Capataz.max_allowed_iterations\n"
    end


    def rewrite_block_symbol_pass(node, len)

      sym = node.children[len - 1].type == :sym ? node.children[len - 1].children[0]: node.children[len - 1].children[0].children[0]

      range = node.children[len - 1].location.expression
      if len > 3
        begin_pos = node.children[len - 2].location.expression.end_pos
        end_pos = node.children[len - 1].location.expression.end_pos
        range = Parser::Source::Range.new(@source_buffer, begin_pos, end_pos)
      end

      remove(range)

      if node.children[1] == :inject or node.children[1] == :reduce
        text_to_insert = "{ |memo, item| \n#{inc_block_iter_counter}::Capataz.handle(memo) #{sym} (item).capataz_slave\n}"
      else
        text_to_insert = " { |item| \n#{inc_block_iter_counter}::Capataz.handle(item).#{sym} \n}"
      end

      insert_after(node.location.expression, text_to_insert)
      @decapatized_nodes << node.children[len - 1]
    end
  end
end