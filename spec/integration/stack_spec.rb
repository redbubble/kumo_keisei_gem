require 'aws-sdk'

def cfn_stack_names()
  cloudformation = Aws::CloudFormation::Client.new
  return cloudformation.describe_stacks().stacks.map{ |x| x.stack_name }.compact
end

def ensure_stack_doesnt_exist(stack_name , it_was_supposed_to_exist=false)
  if cfn_stack_names.include? stack_name
    puts "Deleting #{stack_name} stack"
    puts "...it seems to be left over from a previous test" unless it_was_supposed_to_exist
    cloudformation = Aws::CloudFormation::Client.new
    cloudformation.delete_stack(stack_name: stack_name)
    cloudformation.wait_until(:stack_delete_complete, stack_name: stack_name) { |waiter| waiter.delay = 1; waiter.max_attempts = 90 }
  end
end


describe KumoKeisei::Stack do

  stack_timeout_options = {
    confirmation_timeout: 30,
    waiter_delay: 1,
    waiter_attempts: 90
  }

  environment_name = ENV.fetch('BUILDKITE_BUILD_NUMBER', `whoami`.strip)
  stack_name = "kumokeisei-test"
  stack_full_name = "#{stack_name}-#{environment_name}"

  describe "#apply!" do
    before do
      ensure_stack_doesnt_exist(stack_full_name, false)
    end
    #
    # [
    #   {
    #     :variant => 'no parameters',
    #     :fixture => 'no-parameter-section.json'
    #   },
    #   {
    #     :variant => 'an empty parameter section',
    #     :fixture => 'empty-parameter-section.json'
    #   },
    #   {
    #     :variant => 'parameters which all have defaults',
    #     :fixture => 'all-parameters-have-defaults.json'
    #   }
    # ].each do |scenario|
    #   context "when given a CloudFormation template that has #{scenario[:variant]}" do
    #     after do
    #       ensure_stack_doesnt_exist(stack_full_name, true)
    #     end
    #
    #     it "creates a stack" do
    #       stack_config = {
    #         # config_path: File.join('', 'config'),
    #         template_path: File.join(File.dirname(__FILE__), 'fixtures', "#{scenario[:fixture]}")
    #       }
    #
    #       stack = KumoKeisei::Stack.new(stack_name, environment_name, stack_timeout_options)
    #       stack.apply!(stack_config)
    #       expect cfn_stack_names.to include(stack_full_name)
    #     end
    #   end
    # end

    context "when given a CloudFormation template" do
      context "and a parameter template file exists" do
        it "creates a stack" do
          stack_config = {
            config_path: File.join(File.dirname(__FILE__), 'fixtures'),
            template_path: File.join(File.dirname(__FILE__), 'fixtures', 'one-parameter.json')
          }

          stack = KumoKeisei::Stack.new(stack_name, environment_name, stack_timeout_options)
          stack.apply!(stack_config)
          expect(cfn_stack_names).to include(stack_full_name)
        end

        after do
          ensure_stack_doesnt_exist(stack_full_name, true)
        end
      end

      context "and a parameter template file is not required and does not exist" do
        it "creates a stack" do
          stack_config = {
            template_path: File.join(File.dirname(__FILE__), 'fixtures', 'no-parameter-section.json')
          }

          stack = KumoKeisei::Stack.new(stack_name, environment_name, stack_timeout_options)
          stack.apply!(stack_config)
          expect(cfn_stack_names).to include(stack_full_name)
        end

        after do
          ensure_stack_doesnt_exist(stack_full_name, true)
        end
      end

      context "and a parameter template file is required but does not exist" do
        it "does not create a stack" do
          stack_config = {
            template_path: File.join(File.dirname(__FILE__), 'fixtures', 'one-parameter-no-matching-parameter-template.json')
          }

          stack = KumoKeisei::Stack.new(stack_name, environment_name, stack_timeout_options)
          expect { stack.apply!(stack_config)}.to raise_error(Aws::CloudFormation::Errors::ValidationError)
          expect(cfn_stack_names).not_to include(stack_full_name)
        end

        after do
          ensure_stack_doesnt_exist(stack_full_name, false)
        end
      end
    end

  end
end
