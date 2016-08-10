module KumoKeisei
  class GetStackOutput
    def initialize(aws_stack)
      @aws_stack = aws_stack
    end

    def output(name)
      return nil if @aws_stack.nil?
      outputs_hash = @aws_stack.outputs.reduce({}) { |acc, o| acc.merge(o.output_key.to_s => o.output_value) }
      outputs_hash[name]
    end
  end
end
