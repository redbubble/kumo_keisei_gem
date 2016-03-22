require "json"
require 'shellwords'
require 'aws-sdk'

require_relative "parameter_builder"

module KumoKeisei
  class CloudFormationStack
    UPDATEABLE_STATUSES = [
      'UPDATE_ROLLBACK_COMPLETE',
      'CREATE_COMPLETE',
      'UPDATE_COMPLETE',
      'DELETE_COMPLETE'
    ]

    RECOVERABLE_STATUSES = [
      'ROLLBACK_COMPLETE',
      'ROLLBACK_FAILED'
    ]

    UNRECOVERABLE_STATUSES = [
      'UPDATE_ROLLBACK_FAILED'
    ]

    attr_reader :stack_name

    def initialize(stack_name, stack_template, stack_params_filepath = nil)
      @stack_name = stack_name
      @stack_template = stack_template
      @stack_params_filepath = stack_params_filepath
    end

    def apply!(dynamic_params={})
      if updatable?
        update!(dynamic_params)
      else
        flash_message "Looks like there's a stack called #{@stack_name} that didn't create properly, I'll clean it up for you..."
        ensure_deleted!
        flash_message "Looks like you are creating new stack #{@stack_name}"
        create!(dynamic_params)
      end
    end

    def destroy!
      wait_until_ready(false)
      ensure_deleted!
    end

    private

    def cloudformation
      @cloudformation ||= Aws::CloudFormation::Client.new(load_creds)
    end

    def load_creds
      {
        credentials: Aws::Credentials.new(ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"]),
        region: ENV["AWS_DEFAULT_REGION"]
      }
    end

    def ensure_deleted!
      cloudformation.delete_stack(stack_name: @stack_name)
      cloudformation.wait_until(:stack_delete_complete, stack_name: @stack_name) { |waiter| waiter.delay = 10 }
    end

    def updatable?
      stack = cloudformation.describe_stacks(stack_name: @stack_name).first

      return true if UPDATEABLE_STATUSES.include? stack.stack_status
      return false if RECOVERABLE_STATUSES.include? stack.stack_status
      raise "Stack is in an unrecoverable state" if UNRECOVERABLE_STATUSES.include? stack.stack_status
      raise "Stack is busy, try again soon"
    rescue Aws::CloudFormation::Errors::ValidationError
      false
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

      cloudformation.wait_until(:stack_create_complete, stack_name: @stack_name) { |waiter| waiter.delay 10 }
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

      cloudformation.wait_until(:stack_update_complete, stack_name: @stack_name) { |waiter| waiter.delay 10 }
    end

    def wait_until_ready(raise_on_error=true)
      loop do
        stack = cloudformation.describe_stacks(stack_name: @stack_name).first

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

    def run_command(command, &block)
      puts command
      puts bash.execute(command.strip, &block)
    end

    def flash_message(message)
      puts "\n\n"
      puts "###################=============================------------"
      puts message
      puts "------------=============================###################"
      puts "\n\n"
    end
  end
end
