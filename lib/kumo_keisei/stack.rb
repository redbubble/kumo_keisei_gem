require 'aws-sdk'

module KumoKeisei
  class Stack
    class CreateError < StandardError; end
    class UpdateError < StandardError; end
    class UsageError < StandardError; end

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

    attr_reader :stack_name, :env_name

    def self.exists?(app_name, environment_name)
      self.new(app_name, environment_name).exists?
    end

    def initialize(app_name, environment_name, options = { confirmation_timeout: 30, waiter_delay: 20, waiter_attempts: 90 })
      @env_name = environment_name
      @app_name = app_name
      @stack_name = "#{app_name}-#{ environment_name }"
      @confirmation_timeout = options[:confirmation_timeout]
      @waiter_delay = options[:waiter_delay]
      @waiter_attempts = options[:waiter_attempts]
      prompt_user
    end

    def prompt_user
      puts "WARNING: You are about to lookup/create/update/delete #{@stack_name}."
      puts "We have recently changed the way we name stacks in aws, if #{@stack_name} looks correct, hit 'Y', otherwise hit anything else and read more at 'https://github.com/redbubble/kumo_keisei_gem'"
      continue = $stdin.gets.chomp.downcase
      exit 1 if continue != 'y'
    end

    def apply!(stack_config)
      stack_config.merge!(env_name: @env_name)

      raise UsageError.new('You must provide a :template_path in the stack config hash for an apply! operation') unless stack_config.has_key?(:template_path)

      if updatable?
        update!(stack_config)
      else
        ensure_deleted!
        ConsoleJockey.write_line "Creating your new stack #{@stack_name}"
        create!(stack_config)
      end
    end

    def destroy!
      return if get_stack.nil?

      flash_message "Warning! You are about to delete the CloudFormation Stack #{@stack_name}, enter 'yes' to continue."
      return unless ConsoleJockey.get_confirmation(@confirmation_timeout)

      wait_until_ready(false)
      ensure_deleted!
    end

    def outputs(name)
      return GetStackOutput.new(get_stack).output(name)
    end

    def logical_resource(resource_name)
      response = cloudformation.describe_stack_resource(stack_name: @stack_name, logical_resource_id: resource_name)
      stack_resource = response.stack_resource_detail
      stack_resource.each_pair.reduce({}) {|acc, (k, v)| acc.merge(transform_logical_resource_id(k) => v) }
    end

    def exists?
      !get_stack.nil?
    end

    def config(stack_config)
      raise UsageError.new('You must provide a :config_path in the stack config hash to retrieve the stack\'s config') unless stack_config.has_key?(:config_path)
      environment_config(stack_config).config
    end

    def params_template_path(stack_config)
      stack_config.has_key?(:template_path) ? File.absolute_path(File.join(File.dirname(stack_config[:template_path]), "#{File.basename(stack_config[:template_path], '.*')}.yml.erb")) : nil
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
      cloudformation.wait_until(:stack_delete_complete, stack_name: @stack_name) { |waiter| waiter.delay = @waiter_delay; waiter.max_attempts = @waiter_attempts }
    end

    def updatable?
      stack = get_stack
      return false if stack.nil?

      return true if UPDATEABLE_STATUSES.include? stack.stack_status
      return false if RECOVERABLE_STATUSES.include? stack.stack_status
      raise UpdateError.new("Stack is in an unrecoverable state") if UNRECOVERABLE_STATUSES.include? stack.stack_status
      raise UpdateError.new("Stack is busy, try again soon")
    end

    def create!(stack_config)
      raise StackValidationError.new("The stack name needs to be 32 characters or shorter") if @stack_name.length > 32

      cloudformation.create_stack(
        stack_name: @stack_name,
        template_body: File.read(stack_config[:template_path]),
        parameters: environment_config(stack_config).cf_params,
        capabilities: ["CAPABILITY_IAM"],
        on_failure: "DELETE"
      )

      begin
        cloudformation.wait_until(:stack_create_complete, stack_name: @stack_name) { |waiter| waiter.delay = @waiter_delay; waiter.max_attempts = @waiter_attempts }
      rescue Aws::Waiters::Errors::UnexpectedError => ex
        handle_unexpected_error(ex)
      end
    end

    def update!(stack_config)
      wait_until_ready(false)

      cloudformation.update_stack(
        stack_name: @stack_name,
        template_body: File.read(stack_config[:template_path]),
        parameters: environment_config(stack_config).cf_params,
        capabilities: ["CAPABILITY_IAM"]
      )

      cloudformation.wait_until(:stack_update_complete, stack_name: @stack_name) { |waiter| waiter.delay = @waiter_delay; waiter.max_attempts = @waiter_attempts }
    rescue Aws::CloudFormation::Errors::ValidationError => ex
      raise ex unless ex.message == "No updates are to be performed."
      ConsoleJockey.write_line "No changes need to be applied for #{@stack_name}."
    rescue Aws::Waiters::Errors::FailureStateError
      ConsoleJockey.write_line "Failed to apply the environment update. The stack has been rolled back. It is still safe to apply updates."
      ConsoleJockey.write_line "Find error details in the AWS CloudFormation console: #{stack_events_url}"
      raise UpdateError.new("Stack update failed for #{@stack_name}.")
    end

    def environment_config(stack_config)
      EnvironmentConfig.new(stack_config.merge(params_template_file_path: params_template_path(stack_config)))
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
