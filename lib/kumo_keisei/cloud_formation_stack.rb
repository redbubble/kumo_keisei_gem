require 'aws-sdk'

require_relative "parameter_builder"
require_relative "console_jockey"

module KumoKeisei
  class CloudFormationStack
    class CreateError < StandardError; end
    class UpdateError < StandardError; end

    UPDATEABLE_STATUSES = [
      'UPDATE_ROLLBACK_COMPLETE',
      'CREATE_COMPLETE',
      'UPDATE_COMPLETE'
    ]

    RECOVERABLE_STATUSES = [
      'DELETE_COMPLETE',
      'ROLLBACK_COMPLETE',
      'ROLLBACK_FAILED'
    ]

    UNRECOVERABLE_STATUSES = [
      'UPDATE_ROLLBACK_FAILED'
    ]

    attr_reader :stack_name

    def self.exists?(stack_name)
      self.new(stack_name, nil).exists?
    end

    def initialize(stack_name, stack_template, stack_params_filepath = nil)
      @stack_name = stack_name
      @stack_template = stack_template
      @stack_params_filepath = stack_params_filepath

      flash_message "Stack name: #{stack_name}"
    end

    def apply!(dynamic_params={})
      if updatable?
        update!(dynamic_params)
      else
        ensure_deleted!
        ConsoleJockey.write_line "Creating your new stack #{@stack_name}"
        create!(dynamic_params)
      end
    end

    def destroy!
      return if get_stack.nil?

      wait_until_ready(false)
      ensure_deleted!
    end

    def outputs(output)
      outputs_hash = get_stack.outputs.reduce({}) { |acc, o| acc.merge(o.output_key.to_s => o.output_value) }

      outputs_hash[output]
    end

    def logical_resource(resource_name)
      response = cloudformation.describe_stack_resource(stack_name: @stack_name, logical_resource_id: resource_name)
      stack_resource = response.stack_resource_detail
      stack_resource.each_pair.reduce({}) {|acc, (k, v)| acc.merge(transform_logical_resource_id(k) => v) }
    end

    def exists?
      !get_stack.nil?
    end

    private

    def transform_logical_resource_id(id)
      id.to_s.split('_').map {|w| w.capitalize }.join
    end

    def get_stack(options={})
      @stack = nil if options[:dump_cache]

      @stack ||= cloudformation.describe_stacks(stack_name: @stack_name).stacks.find { |stack| stack.stack_name == @stack_name }
    rescue Aws::CloudFormation::Errors::ValidationError
      nil
    end

    def cloudformation
      @cloudformation ||= Aws::CloudFormation::Client.new
    end

    def ensure_deleted!
      stack = get_stack
      return if stack.nil?
      return if stack.stack_status == 'DELETE_COMPLETE'

      ConsoleJockey.write_line "There's a previous stack called #{@stack_name} that didn't create properly, I'll clean it up for you..."
      cloudformation.delete_stack(stack_name: @stack_name)
      cloudformation.wait_until(:stack_delete_complete, stack_name: @stack_name) { |waiter| waiter.delay = 20; waiter.max_attempts = 45 }
    end

    def updatable?
      stack = get_stack
      return false if stack.nil?

      return true if UPDATEABLE_STATUSES.include? stack.stack_status
      return false if RECOVERABLE_STATUSES.include? stack.stack_status
      raise UpdateError.new("Stack is in an unrecoverable state") if UNRECOVERABLE_STATUSES.include? stack.stack_status
      raise UpdateError.new("Stack is busy, try again soon")
    end

    def create!(dynamic_params)
      cloudformation_params = ParameterBuilder.new(dynamic_params, @stack_params_filepath).params
      cloudformation.create_stack(
        stack_name: @stack_name,
        template_body: File.read(@stack_template),
        parameters: cloudformation_params,
        capabilities: ["CAPABILITY_IAM"],
        on_failure: "DELETE"
      )

      begin
        cloudformation.wait_until(:stack_create_complete, stack_name: @stack_name) { |waiter| waiter.delay = 20; waiter.max_attempts = 45 }
      rescue Aws::Waiters::Errors::UnexpectedError => ex
        handle_unexpected_error(ex)
      end
    end

    def update!(dynamic_params={})
      cloudformation_params = ParameterBuilder.new(dynamic_params, @stack_params_filepath).params
      wait_until_ready(false)

      cloudformation.update_stack(
        stack_name: @stack_name,
        template_body: File.read(@stack_template),
        parameters: cloudformation_params,
        capabilities: ["CAPABILITY_IAM"]
      )

      cloudformation.wait_until(:stack_update_complete, stack_name: @stack_name) { |waiter| waiter.delay = 20; waiter.max_attempts = 45 }
    rescue Aws::CloudFormation::Errors::ValidationError => ex
      raise ex unless ex.message == "No updates are to be performed."
      ConsoleJockey.write_line "No changes need to be applied for #{@stack_name}."
    rescue Aws::Waiters::Errors::FailureStateError => ex
      ConsoleJockey.write_line "Failed to apply the environment update. The stack has been rolled back. It is still safe to apply updates."
      ConsoleJockey.write_line "Find error details in the AWS CloudFormation console: #{stack_events_url}"
      raise UpdateError.new("Stack update failed for #{@stack_name}.")
    end

    def stack_events_url
      "https://console.aws.amazon.com/cloudformation/home?region=#{ENV['AWS_DEFAULT_REGION']}#/stacks?filter=active&tab=events&stackId=#{get_stack.stack_id}"
    end

    def wait_until_ready(raise_on_error=true)
      loop do
        stack = get_stack(dump_cache: true)

        if stack_ready?(stack.stack_status)
          if raise_on_error && stack_operation_failed?(stack.stack_status)
            raise stack.stack_status
          end

          break
        end
        puts "waiting for #{@stack_name} to be READY, current: #{last_event_status}"
        sleep 10
      end
    rescue Aws::CloudFormation::Errors::ValidationError
      nil
    end

    def stack_ready?(last_event_status)
      last_event_status =~ /COMPLETE/ || last_event_status =~ /ROLLBACK_FAILED/
    end

    def stack_operation_failed?(last_event_status)
      last_event_status =~ /ROLLBACK/
    end

    def handle_unexpected_error(error)
      if error.message =~ /does not exist/
        ConsoleJockey.write_line "There was an error during stack creation for #{@stack_name}, and the stack has been cleaned up."
        raise CreateError.new("There was an error during stack creation. The stack has been deleted.")
      else
        raise error
      end
    end

    def flash_message(message)
      ConsoleJockey.flash_message(message)
    end
  end
end
