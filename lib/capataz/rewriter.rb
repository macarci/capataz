require 'capataz/source_rewriter'

module Capataz

  class Rewriter < Parser::Rewriter

    attr_reader :logs

    def initialize(options = {})
      @options = options || {}
      @logs = options[:logs] || {}
      @self_linker = options[:self_linker]
      @self_send_prefixer = options[:self_send_prefixer]

      @block_iter_counter = 0

      @capatized_nodes = Set.new
      @decapatize_skip_nodes = Set.new

      @curr_branch_nodes = []
      @limited_methods = Set.new
      @invocations_insertions = []

      @last_signif_node_pos = -1
      @last_signif_node_type = nil

      @iteration_counter_prefix = options[:iteration_counter_prefix]
      @invoke_counter_prefix = options[:invoke_counter_prefix]
    end

    def iteration_counter_prefix
      if @iteration_counter_prefix.respond_to?(:call)
        @iteration_counter_prefix.call
      else
        @iteration_counter_prefix || '_it_c'
      end + '_'
    end

    OPERATORS =
      {
        '**': 'exp',
        '+': 'add',
        '-': 'sub',
        '!': 'neg',
        '~': 'reg',
        '*': 'mult',
        '/': 'div',
        '%': 'mod',
        '<<': 'lshift',
        '>>': 'rshift',
        '&': 'bitwise_and',
        '|': 'bitwise_or',
        '^': 'bitwise_or',
        '>': 'gt',
        '>=': 'gte',
        '<': 'lt',
        '<=': 'lte',
        '==': 'eq',
        '===': 'rship',
        '<=>': 'comp',
        '!=': 'neq',
        '=~': 'regex_eq',
        '!~': 'not_regex',
        '&&': 'and',
        '||': 'or',
        '..': 'range',
        '...': 'ex_range',
        '=': 'assign',
        '+=': 'assign_add',
        '-=': 'assign_sub',
        '&&=': 'assign_and',
        '||=': 'assign_or',
      }

    def invoke_counter_for(method)
      @limited_methods << method
      prefix =
        if @invoke_counter_prefix.respond_to?(:call)
          @invoke_counter_prefix.call
        else
          @invoke_counter_prefix || '_invk_c'
        end + '_'
      if (op = OPERATORS[method.to_s.to_sym])
        method = "0#{op}"
      end
      "#{prefix}#{method}"
    end

    def rewrite(source_buffer, ast)
      @source_buffer = source_buffer

      @logs.clear
      @capatized_nodes.clear
      @source_rewriter = Capataz::SourceRewriter.new(source_buffer)

      process(ast)

      @invocations_insertions.each do
      |invocation|
        if invocation[0] == :insert_before_multi
          @source_rewriter.insert_before_multi(invocation[1], invocation[2])
        elsif invocation[0] == :insert_after_multi
          @source_rewriter.insert_after_multi(invocation[1], invocation[2])
        end
      end

      @source_rewriter.preprocess
      new_source = @source_rewriter.process

      counters_initializers = ''
      @block_iter_counter.downto(1) { |i| counters_initializers = "#{iteration_counter_prefix}#{i} ||= 0; #{counters_initializers}" }
      @limited_methods.each { |method| counters_initializers = "#{invoke_counter_for(method)} ||= 0; #{counters_initializers}" }
      new_source.insert(@options[:code_start] || 0, counters_initializers)
    end

    def on_pair(node)
      super
      decapatize(node.children[1])
    end

    def on_array(node)
      super
      node.children.each { |child| decapatize(child) }
    end

    def on_block(node)
      first_range = Parser::Source::Range.new(@source_buffer, node.location.begin.begin_pos, node.location.begin.end_pos)
      replace(first_range, '{')
      second_range = Parser::Source::Range.new(@source_buffer, node.location.end.begin_pos, node.location.end.end_pos)
      replace(second_range, '}')

      if node.children[1].children.length > 0
        insert_after(node.children[1].location.end, inc_block_iter_counter)
      else
        insert_after(node.location.begin, inc_block_iter_counter)
      end

      @curr_branch_nodes.push(node)
      @last_signif_node_pos = @curr_branch_nodes.length - 1
      @last_signif_node_type = node.type
      super
      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
      end
    end

    def on_for(node)
      if node.children[1].location.end
        insert_after(node.children[1].location.end, inc_block_iter_counter)
      else
        insert_after(node.children[1].location.expression, inc_block_iter_counter)
      end
      @curr_branch_nodes.push(node)
      @last_signif_node_pos = @curr_branch_nodes.length - 1
      @last_signif_node_type = node.type
      super
      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
      end
    end

    def on_kwbegin(node)
      insert_after(node.location.begin, inc_block_iter_counter)
      super
    end

    def on_while(node)
      insert_after(node.children[0].location.expression, inc_block_iter_counter)
      @curr_branch_nodes.push(node)
      @last_signif_node_pos = @curr_branch_nodes.length - 1
      @last_signif_node_type = node.type
      super
      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
      end
    end


    def on_until(node)
      insert_after(node.children[0].location.expression, inc_block_iter_counter)
      @curr_branch_nodes.push(node)
      @last_signif_node_pos = @curr_branch_nodes.length - 1
      @last_signif_node_type = node.type
      super
      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
      end
    end


    def on_send(node)
      @curr_branch_nodes.push(node)

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

      if node.type == :send
        if Capataz.maximum_invocations || Capataz.maximum_invocations_of(node.children[1])
          if @last_signif_node_pos >= 0
            if @last_signif_node_type == :for
              if @curr_branch_nodes[@last_signif_node_pos + 1] == @curr_branch_nodes[@last_signif_node_pos].children[1]
                @invocations_insertions << [:insert_before_multi, @curr_branch_nodes[@last_signif_node_pos].location.expression, new_invocation(node.children[1])]
              elsif @curr_branch_nodes[@last_signif_node_pos + 1] == @curr_branch_nodes[@last_signif_node_pos].children[2]
                @invocations_insertions << [:insert_before_multi, @curr_branch_nodes[@last_signif_node_pos + 1].location.expression, new_invocation(node.children[1])]
              end
            elsif @last_signif_node_type == :while or @last_signif_node_type == :until
              @invocations_insertions << [:insert_after_multi, @curr_branch_nodes[@last_signif_node_pos].children[0].location.expression, new_invocation(node.children[1])]
            elsif @last_signif_node_type == :if
              if @curr_branch_nodes[@last_signif_node_pos + 1] == @curr_branch_nodes[@last_signif_node_pos].children[0]
                @invocations_insertions << [:insert_before_multi, @curr_branch_nodes[@last_signif_node_pos].location.expression, new_invocation(node.children[1])]
              elsif @curr_branch_nodes[@last_signif_node_pos + 1] == @curr_branch_nodes[@last_signif_node_pos].children[1] or \
              @curr_branch_nodes[@last_signif_node_pos + 1] == @curr_branch_nodes[@last_signif_node_pos].children[2]
                @invocations_insertions << [:insert_before_multi, @curr_branch_nodes[@last_signif_node_pos + 1].location.expression, new_invocation(node.children[1])]
              end
            elsif @last_signif_node_type == :block
              @invocations_insertions << [:insert_before_multi, node.location.expression, new_invocation(node.children[1])]
            elsif @last_signif_node_type == :lvasgn
              @invocations_insertions << [:insert_before_multi, @curr_branch_nodes[@last_signif_node_pos].location.expression, new_invocation(node.children[1])]
            end
          else
            @invocations_insertions << [:insert_before_multi, @curr_branch_nodes[0].location.expression, new_invocation(node.children[1])]
          end
        end
      end

      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
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
      @curr_branch_nodes.push(node)
      if @curr_branch_nodes.length > 1
        if @curr_branch_nodes[@curr_branch_nodes.length - 2].type != :for or \
           @curr_branch_nodes[@curr_branch_nodes.length - 2].children[0] != node
          @last_signif_node_pos = @curr_branch_nodes.length - 1
          @last_signif_node_type = node.type
        end
      end

      super
      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
      end
      capatize(node.children[1])
    end

    def on_if(node)
      @curr_branch_nodes.push(node)
      @last_signif_node_pos = @curr_branch_nodes.length - 1
      @last_signif_node_type = node.type
      super
      @curr_branch_nodes.pop
      if @curr_branch_nodes.length == 0
        @last_signif_node_pos = -1
      end
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
        if options.empty?
          @source_rewriter.insert_after_multi(node.location.expression, ')')
        else
          @source_rewriter.insert_after_multi(node.location.expression, ", #{options.to_a.collect { |item| "#{item[0]}: #{item[1]}" }.join(',')})")
        end
      end
    end

    def decapatize(node)
      unless @decapatize_skip_nodes.include?(node) || [:hash, :sym, :str, :int, :true, :false].include?(node.type)
        @source_rewriter.insert_before_multi(node.location.expression, '(')
        @source_rewriter.insert_after_multi(node.location.expression, ').capataz_slave')
      end
    end

    def const_from(node)
      if node
        const_from(node.children[0]) + '::' + node.children[1].to_s
      else
        ''
      end
    end

    def inc_block_iter_counter
      if Capataz.maximum_iterations
        @block_iter_counter += 1
        bc = @block_iter_counter
        " ;#{iteration_counter_prefix}#{bc} += 1; ::Capataz.check_iteration_counter(#{iteration_counter_prefix}#{bc}); "
      else
        ''
      end
    end

    def new_invocation(method)
      if Capataz.maximum_invocations_of(method)
        " ;#{invoke_counter_for(method)} += 1; ::Capataz.check_invocation_counter(:#{method}, #{invoke_counter_for(method)}); "
      else
        ''
      end
    end

    def rewrite_block_symbol_pass(node, len)
      sym = node.children[len - 1].type == :sym ? node.children[len - 1].children[0] : node.children[len - 1].children[0].children[0]

      range = node.children[len - 1].location.expression
      if len > 3
        begin_pos = node.children[len - 2].location.expression.end_pos
        end_pos = node.children[len - 1].location.expression.end_pos
        range = Parser::Source::Range.new(@source_buffer, begin_pos, end_pos)
      end

      remove(range)

      if node.children[1] == :inject or node.children[1] == :reduce
        text_to_insert = "{ |memo, item| #{inc_block_iter_counter} #{new_invocation(sym)} ::Capataz.handle(memo) #{sym} (item).capataz_slave };"
      else
        text_to_insert = " { |item| #{inc_block_iter_counter} #{new_invocation(sym)} ::Capataz.handle(item).#{sym} };"
      end

      insert_after(node.location.expression, text_to_insert)
      @decapatize_skip_nodes << node.children[len - 1]
    end
  end
end