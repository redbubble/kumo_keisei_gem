require 'aws-sdk'

def stack_exists?(stack_name)
  cloudformation = Aws::CloudFormation::Client.new
  cloudformation.describe_stacks({ stack_name: stack_name })
  true
rescue Aws::CloudFormation::Errors::ValidationError
  false
end

describe KumoKeisei::Stack do
  let(:environment_name) { ENV.fetch('BUILDKITE_BUILD_NUMBER', `whoami`.strip) }
  let(:stack_name) { "kumokeisei-test" }
  let(:stack_full_name) { "#{stack_name}-#{environment_name}" }

  let(:stack_timeout_options) do
    {
      confirmation_timeout: 30,
      waiter_delay: 1,
      waiter_attempts: 90
    }
  end

  after do
    if stack_exists?(stack_full_name)
      cloudformation = Aws::CloudFormation::Client.new
      cloudformation.delete_stack(stack_name: stack_full_name)
      cloudformation.wait_until(:stack_delete_complete, stack_name: stack_full_name) { |waiter| waiter.delay = 1; waiter.max_attempts = 90 }
    end
  end

  describe "#apply!" do
    let(:stack) { KumoKeisei::Stack.new(stack_name, environment_name, stack_timeout_options) }
    subject { stack.apply!(stack_config) }

    context "when given a CloudFormation template" do
      context "and a parameter template file exists" do
        let(:stack_config) do
          {
            config_path: File.join(File.dirname(__FILE__), 'fixtures'),
            template_path: File.join(File.dirname(__FILE__), 'fixtures', 'one-parameter.json')
          }
        end

        it "creates a stack" do
          subject
          expect(stack_exists?(stack_full_name)).to be true
        end
      end

      context "and a parameter template file is not required and does not exist" do
        let(:stack_config) do
          {
            template_path: File.join(File.dirname(__FILE__), 'fixtures', 'no-parameter-section.json')
          }
        end

        it "creates a stack" do
          subject
          expect(stack_exists?(stack_full_name)).to be true
        end
      end

      context "and a parameter template file is required but does not exist" do
        let(:stack_config) do
          {
            template_path: File.join(File.dirname(__FILE__), 'fixtures', 'one-parameter-no-matching-parameter-template.json')
          }
        end

        it "does not create a stack" do
          expect { subject }.to raise_error(Aws::CloudFormation::Errors::ValidationError)
          expect(stack_exists?(stack_full_name)).to be false
        end
      end
    end

  end
end
