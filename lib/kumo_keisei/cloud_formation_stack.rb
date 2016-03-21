require "json"
require 'shellwords'
require 'aws-sdk'

require_relative "bash"

module KumoKeisei

  class CloudFormationStack
    class ParseError < StandardError; end
    class AwsCliError < StandardError; end

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

    attr_reader :stack_name, :bash

    def self.exists?(stack_name)
      Bash.new.exit_status_for("aws cloudformation describe-stack-resources --stack-name #{stack_name}") == 0
    end

    def initialize(stack_name, stack_template, stack_params_filepath = nil)
      @stack_name = stack_name
      @stack_template = stack_template
      @stack_params_filepath = stack_params_filepath
      @bash = Bash.new
    end

    def apply!(dynamic_params={})
      if updatable?
        update!(dynamic_params)
      else
        flash_message "Looks like there's a stack called #{stack_name} that didn't create properly, I'll clean it up for you..."
        ensure_deleted!
        flash_message "Looks like you are creating new stack #{stack_name}"
        create_alt!(dynamic_params)
      end
    end

    def destroy!
      wait_until_ready(false)
      run_command("aws cloudformation delete-stack --stack-name #{stack_name}") do |response, exit_status|
        if exit_status > 0
          puts response
          raise AwsCliError.new response
        end
      end
      wait_until_ready
    end

    def logical_resource(name)
      app_resource_description = bash.execute("aws cloudformation describe-stack-resource --stack-name=#{@stack_name} --logical-resource-id=#{name}")
      JSON.parse(app_resource_description)["StackResourceDetail"]
    end

    def fetch_param(param_key)
      stack_response = bash.execute("aws cloudformation describe-stacks --stack-name=#{@stack_name}")
      param = JSON.parse(stack_response)["Stacks"].first["Parameters"].find { |param| param["ParameterKey"] == param_key } rescue raise(ParseError, "Could not parse response from AWS: #{stack_response}")
      param ? param["ParameterValue"] : nil
    end

    def outputs(key)
      stacks_json = bash.execute("aws cloudformation describe-stacks --stack-name=#{@stack_name}")
      outputs = JSON.parse(stacks_json)["Stacks"].first["Outputs"]
      entry = outputs.find { |e| e["OutputKey"] == key }
      entry["OutputValue"]
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
      cloudformation.delete_stack(stack_name: stack_name)
      cloudformation.wait_until(:stack_delete_complete, stack_name: stack_name) { |waiter| waiter.delay = 10 }
    end

    def updatable?
      stack = cloudformation.describe_stacks(name: stack_name).first

      return true if UPDATEABLE_STATUSES.include? stack.stack_status
      return false if RECOVERABLE_STATUSES.include? stack.stack_status
    rescue Aws::CloudFormation::Errors::ValidationError
      false
    end

    def create_alt!(dynamic_params)
      #fix params
      cloudformation.create_stack(
        stack_name: "",
        template_body: "",
        parameters: [],
        capabilities: ["CAPABILITY_IAM"],
        on_failure: "DELETE",
      )

      cloudformation.wait_until(:stack_create_complete, stack_name: stack_name) { |waiter| waiter.delay 10 }
    end

    def exists?
      CloudFormationStack.exists?(stack_name)
    end

    def update!(dynamic_params={})
      wait_until_ready(false)
      run_command("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://#{@stack_template} #{command_line_params(dynamic_params)}") do |response, exit_status|
        if exit_status > 0
          if response =~ /No updates are to be performed/
            puts "No updates are to be performed"
            return
          end
          puts response
          raise AwsCliError.new response
        end
      end
    end

    def create!(dynamic_params={})
      run_command("aws cloudformation create-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://#{@stack_template} #{command_line_params(dynamic_params)}") do |response, exit_status|
        puts response
        raise AwsCliError.new response unless exit_status == 0
      end
    end

    def wait_until_ready(raise_on_error=true)
      loop do
        stack_events = bash.execute("aws cloudformation describe-stacks --stack-name #{stack_name}")
        break if stack_events =~ /does not exist/
        last_event_status = JSON.parse(stack_events)["Stacks"].first["StackStatus"]
        if stack_ready?(last_event_status)
          if raise_on_error && stack_failed?(last_event_status)
            raise last_event_status
          end
          break
        end
        puts "waiting for #{stack_name} to be READY, current: #{last_event_status}"
        sleep 1
      end
    end

    def stack_ready?(last_event_status)
      last_event_status =~ /COMPLETE/ || last_event_status =~ /ROLLBACK_FAILED/
    end

    def stack_failed?(last_event_status)
      last_event_status =~ /ROLLBACK/
    end

    def run_command(command, &block)
      puts command
      puts bash.execute(command.strip, &block)
    end

    def command_line_params(dynamic_params = {})
      params = file_params.merge(dynamic_params).map do |key, value|
        {
         "ParameterKey" => key,
         "ParameterValue" => value
        }
      end

      return "" if params.empty?

      parameters_string = Shellwords.escape(params.to_json)
       "--parameters #{parameters_string}"
    end

    def file_params
      return {} unless (@stack_params_filepath && File.exist?(@stack_params_filepath))
      file = File.read(@stack_params_filepath)
      json = JSON.parse(file)

      json.reduce({}) do |acc, item|
        acc[item['ParameterKey'].to_sym] = item['ParameterValue']
        acc
      end
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
