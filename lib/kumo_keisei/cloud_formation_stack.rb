require "json"
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

    def logical_resource(name)
      app_resource_description = bash.execute("aws cloudformation describe-stack-resource --stack-name=#{@stack_name} --logical-resource-id=#{name}")
      JSON.parse(app_resource_description)["StackResourceDetail"]
    end

    private

    def exists?
      bash.exit_status_for("aws cloudformation describe-stack-resources --stack-name #{stack_name}") == 0
    end

    def update!(dynamic_params={})
      wait_until_ready
      run_command("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://#{@base_template} #{command_line_params(dynamic_params)}")
    end

    def create!(dynamic_params={})
      run_command("aws cloudformation create-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://#{@base_template} #{command_line_params(dynamic_params)}")
    end

    def wait_until_ready
      loop do
        stack_events      = bash.execute("aws cloudformation describe-stacks --stack-name #{stack_name}")
        last_event_status = JSON.parse(stack_events)["Stacks"].first["StackStatus"]
        break if last_event_status =~ /COMPLETE/
        puts "waiting for #{stack_name} to be READY, current: #{last_event_status}"
        sleep 1
      end
    end

    def run_command(command)
      puts command
      result = bash.execute(command.strip)
      if result =~ /No updates are to be performed/
        puts "No updates are to be performed"
        return
      end
      puts result
    end

    def file_params
      return [] unless (@env_template && File.exist?(@env_template))
      file = File.read(@env_template)
      JSON.parse(file)
    end

    def command_line_params(dynamic_params = {})
      params = file_params.map do |k|
        "ParameterKey=#{k['ParameterKey']},ParameterValue=#{k['ParameterValue']}"
      end

      sth = dynamic_params.map do |key, value|
        "ParameterKey=#{key},ParameterValue=#{value}"
      end

      return "" if sth.empty? && params.empty?

       "--parameters #{sth.join(" ")} #{params.join(" ")}"
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
