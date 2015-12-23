require "json"
require 'shellwords'

require_relative "bash"

module KumoKeisei

  class CloudFormationStack

    attr_reader :stack_name, :bash

    def initialize(cf_opts = {})
      @stack_name    = cf_opts.fetch(:stack)
      @base_template = cf_opts.fetch(:base_template)
      @env_template   = cf_opts.fetch(:env_template, nil)
      @bash = Bash.new
    end

    def apply!(dynamic_params={})
      if exists?
        update!(dynamic_params)
      else
        flash_message "Looks like you are creating new stack #{stack_name}"
        create!(dynamic_params)
      end
      wait_until_ready
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

    def outputs(key)
      stacks_json = bash.execute("aws cloudformation describe-stacks --stack-name=#{@stack_name}")
      outputs = JSON.parse(stacks_json)["Stacks"].first["Outputs"]
      entry = outputs.find { |e| e["OutputKey"] == key }
      entry["OutputValue"]
    end

    private

    def exists?
      bash.exit_status_for("aws cloudformation describe-stack-resources --stack-name #{stack_name}") == 0
    end

    def update!(dynamic_params={})
      wait_until_ready(false)
      run_command("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://#{@base_template} #{command_line_params(dynamic_params)}") do |response, exit_status|
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
      run_command("aws cloudformation create-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://#{@base_template} #{command_line_params(dynamic_params)}") do |response, exit_status|
        puts response
        raise AwsCliError.new response unless exit_status == 0
      end
    end

    def wait_until_ready(raise_on_error=true)
      loop do
        stack_events      = bash.execute("aws cloudformation describe-stacks --stack-name #{stack_name}")
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
      return {} unless (@env_template && File.exist?(@env_template))
      file = File.read(@env_template)
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

    class AwsCliError < StandardError; end
  end
end
