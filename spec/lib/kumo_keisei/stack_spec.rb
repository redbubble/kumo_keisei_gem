require 'ostruct'

describe KumoKeisei::Stack do

  def stack_result_list_with_status(status, stack_name)
    stack = OpenStruct.new(stack_status: status, stack_name: stack_name)
    OpenStruct.new(stacks: [stack])
  end

  let(:app_name) { "my-stack" }
  let(:environment_name) { 'non-production' }
  let(:stack_name) { "#{app_name}-#{environment_name}" }
  let(:stack_template_name) { "#{app_name}-#{environment_name}" }
  let(:stack_cfntemplate_filename) { "#{stack_template_name}.json" }
  let(:stack_cfnparams_filename) { "#{stack_template_name}.yml.erb" }
  let(:cloudformation) { instance_double(Aws::CloudFormation::Client) }
  let(:happy_stack_status) { "CREATE_COMPLETE" }
  let(:named_cf_stack) { double(stack_status: happy_stack_status, stack_name: stack_name, stack_id: nil) }
  let(:cf_stack) { double(stacks: [named_cf_stack]) }
  let(:parameter_builder) { instance_double(KumoKeisei::ParameterBuilder, params: {}) }
  let(:stack_template_body) { double(:stack_template_body) }
  let(:cf_stack_update_params) do
    {
      stack_name: stack_name,
      template_body: stack_template_body,
      parameters: {},
      capabilities: ["CAPABILITY_IAM"]
    }
  end
  let(:cf_stack_create_params) do
    cf_stack_update_params.merge(on_failure: "DELETE")
  end
  let(:confirmation_timeout) { 30 }
  subject(:instance) { KumoKeisei::Stack.new(app_name, environment_name) }
  let(:stack_config) {
    {
      config_path: 'config-path',
      template_path: stack_cfntemplate_filename,
      injected_config: { 'VpcId' => 'vpc-id' },
      env_name: 'non-production'
    }
  }

  before do
    allow(KumoKeisei::ConsoleJockey).to receive(:flash_message)
    allow(KumoKeisei::ConsoleJockey).to receive(:write_line).and_return(nil)
    allow(KumoKeisei::ConsoleJockey).to receive(:get_confirmation).with(confirmation_timeout).and_return(false)
    allow(Aws::CloudFormation::Client).to receive(:new).and_return(cloudformation)
    allow(cloudformation).to receive(:describe_stacks).with({stack_name: stack_name}).and_return(cf_stack)
    allow(KumoKeisei::ParameterBuilder).to receive(:new).and_return(parameter_builder)
    allow(File).to receive(:read).with(stack_cfntemplate_filename).and_return(stack_template_body)
    allow(KumoKeisei::EnvironmentConfig).to receive(:new).with(stack_config.merge(params_template_file_path: "/#{stack_cfnparams_filename}")).and_return(double(:environment_config, cf_params: {}))
    Dir.chdir('/')
  end

  describe "#destroy!" do
    it "notifies the user of what it is about to delete" do
      expect(KumoKeisei::ConsoleJockey).to receive(:flash_message).with("Warning! You are about to delete the CloudFormation Stack #{stack_name}, enter 'yes' to continue.")
      subject.destroy!
    end

    it "does delete the stack if the user confirms" do
      expect(KumoKeisei::ConsoleJockey).to receive(:get_confirmation).with(confirmation_timeout).and_return(true)
      expect(cloudformation).to receive(:delete_stack).with({stack_name: stack_name}).and_return(cf_stack)
      allow(cloudformation).to receive(:wait_until).with(:stack_delete_complete, stack_name: stack_name).and_return(nil)
      subject.destroy!
    end

    it "does not delete the stack if the the user refuses confirmation" do
      expect(KumoKeisei::ConsoleJockey).to receive(:get_confirmation).with(confirmation_timeout).and_return(false)
      subject.destroy!
    end

  end

  describe "#apply!" do
    context "when you don't specify the location of the Cfn template" do
      let(:stack_config) {
        {
          config_path: 'config-path',
          injected_config: { 'VpcId' => 'vpc-id' },
          env_name: 'non-production'
        }
      }

      it "complains" do
        expect { subject.apply!(stack_config) }.to raise_error(KumoKeisei::Stack::UsageError)
      end
    end

    context "when the stack is updatable" do
      UPDATEABLE_STATUSES = ['UPDATE_ROLLBACK_COMPLETE', 'CREATE_COMPLETE', 'UPDATE_COMPLETE']

      context "when the stack has changed" do
        before do
          allow(cloudformation).to receive(:wait_until).with(:stack_update_complete, stack_name: stack_name).and_return(nil)
        end

        UPDATEABLE_STATUSES.each do |stack_status|
          it "updates the stack when in #{stack_status} status" do
            allow(cloudformation).to receive(:describe_stacks).with({stack_name: stack_name}).and_return(
                                       stack_result_list_with_status(stack_status, stack_name),
                                       stack_result_list_with_status("UPDATE_COMPLETE", stack_name)
                                     )
            expect(cloudformation).to receive(:update_stack).with(cf_stack_update_params).and_return("stack_id")
            subject.apply!(stack_config)
          end
        end

        it "politely informs the user of any failures" do
          allow(cloudformation).to receive(:wait_until)
                                    .with(:stack_update_complete, stack_name: stack_name)
                                    .and_raise(Aws::Waiters::Errors::FailureStateError.new(""))

          allow(cloudformation).to receive(:update_stack).with(cf_stack_update_params).and_return("stack_id")
          expect(KumoKeisei::ConsoleJockey).to receive(:write_line).with("Failed to apply the environment update. The stack has been rolled back. It is still safe to apply updates.")

          expect { subject.apply!(stack_config) }.to raise_error(KumoKeisei::Stack::UpdateError)
        end
      end

      context "when the stack has not changed" do
        let(:error) { Aws::CloudFormation::Errors::ValidationError.new('', 'No updates are to be performed.') }

        UPDATEABLE_STATUSES.each do |stack_status|
          it "reports that nothing has changed when in #{stack_status} status" do
            allow(cloudformation).to receive(:describe_stacks)
                                      .with({stack_name: stack_name})
                                      .and_return(stack_result_list_with_status(stack_status, stack_name))

            expect(cloudformation).to receive(:update_stack).with(cf_stack_update_params).and_raise(error)

            subject.apply!(stack_config)
          end
        end
      end
    end

    context "when the stack is not updatable" do
      before do
        allow(cloudformation).to receive(:wait_until).with(:stack_delete_complete, stack_name: stack_name).and_return(nil)
        allow(cloudformation).to receive(:wait_until).with(:stack_create_complete, stack_name: stack_name).and_return(nil)
        allow(cloudformation).to receive(:delete_stack).with(stack_name: stack_name)
      end

      context "and the stack has status DELETE_COMPLETE" do

        it "creates the stack and does not attempt to delete the stack" do
          expect(cloudformation).not_to receive(:delete_stack)
          allow(cloudformation).to receive(:describe_stacks).with(stack_name: stack_name).and_return(stack_result_list_with_status('DELETE_COMPLETE', stack_name))
          expect(cloudformation).to receive(:create_stack).with(cf_stack_create_params)
          subject.apply!(stack_config)
        end
      end

      context "and the stack does not exist" do
        it "creates the stack" do
          allow(cloudformation).to receive(:delete_stack)
          allow(cloudformation).to receive(:describe_stacks).with(stack_name: stack_name).and_raise(Aws::CloudFormation::Errors::ValidationError.new('',''))
          expect(cloudformation).to receive(:create_stack).with(cf_stack_create_params)
          subject.apply!(stack_config)
        end

        it "shows a friendly error message if the stack had issues during creation" do
          @call_count = 0

          allow(cloudformation).to receive(:delete_stack)
          allow(cloudformation).to receive(:describe_stacks).with(stack_name: stack_name) do
            @call_count += 1

            raise Aws::CloudFormation::Errors::ValidationError.new('','') if @call_count > 1

            OpenStruct.new(stacks: [])
          end
          allow(cloudformation).to receive(:create_stack).with(cf_stack_create_params)

          error = Aws::Waiters::Errors::UnexpectedError.new(RuntimeError.new("Stack with id #{stack_name} does not exist"))
          allow(cloudformation).to receive(:wait_until).with(:stack_create_complete, stack_name: stack_name).and_raise(error)

          expect(KumoKeisei::ConsoleJockey).to receive(:write_line).with(/There was an error during stack creation for #{stack_name}, and the stack has been cleaned up./).and_return nil
          expect { subject.apply!(stack_config) }.to raise_error(KumoKeisei::Stack::CreateError)
        end
      end

      context "and the stack is in ROLLBACK_COMPLETE, or ROLLBACK_FAILED" do
        it "deletes the dead stack and creates a new one" do
          allow(cloudformation).to receive(:describe_stacks).and_return(stack_result_list_with_status("ROLLBACK_COMPLETE", stack_name))

          expect(cloudformation).to receive(:delete_stack).with(stack_name: stack_name)
          expect(cloudformation).to receive(:create_stack)

          allow(cloudformation).to receive(:wait_until).with(:stack_create_complete, stack_name: stack_name).and_return(nil)

          subject.apply!(stack_config)
        end
      end

      context "and the stack in in UPDATE_ROLLBACK_FAILED" do
        it "should blow up" do
          allow(cloudformation).to receive(:describe_stacks).and_return(stack_result_list_with_status("UPDATE_ROLLBACK_FAILED", stack_name))

          expect { subject.apply!(stack_config) }.to raise_error("Stack is in an unrecoverable state")
        end
      end

      context "and the stack is busy" do
        it "should blow up" do
          allow(cloudformation).to receive(:describe_stacks).and_return(stack_result_list_with_status("UPDATE_IN_PROGRESS", stack_name))

          expect { subject.apply!(stack_config) }.to raise_error("Stack is busy, try again soon")
        end
      end

      it "accepts short stack names" do
        allow(cloudformation).to receive(:wait_until).with(:stack_update_complete, stack_name: stack_name)
        allow(cloudformation).to receive(:update_stack)

        subject.apply!(stack_config)
      end

      context "a stack name that is too long" do
        let(:app_name) { "this-will-create-a-very-long-stack-name-that-will-break-aws" }

        it "blows up since the ELB names have to be 32 or shorter" do
          allow(cloudformation).to receive(:wait_until).with(:stack_update_complete, stack_name: stack_name)
          allow(cloudformation).to receive(:update_stack)
          allow(subject).to receive(:updatable?).and_return(false)

          expect { subject.apply!(stack_config) }.to raise_error(KumoKeisei::StackValidationError, "The stack name needs to be 32 characters or shorter")
        end
      end
    end

    describe "#outputs" do
      let(:name) { "Key" }
      subject { instance.outputs(name) }

      let(:get_stack_output) { double(:get_stack_output) }

      it "delegates output retrieval to GetStackOutput" do
        expect(KumoKeisei::GetStackOutput).to receive(:new).with(named_cf_stack).and_return(get_stack_output)
        expect(get_stack_output).to receive(:output).with(name).and_return('Value')
        expect(subject).to eq("Value")
      end
    end

    describe "#logical_resource" do
      let(:stack_resource_detail) { OpenStruct.new(logical_resource_id: "with-a-fox", physical_resource_id: "i-am-sam",  resource_type: "green-eggs-and-ham")}
      let(:response) { double(:response, stack_resource_detail: stack_resource_detail) }
      let(:stack_resource_name) { "with-a-fox" }

      it "returns a hash of the stack resource detail params" do
        allow(cloudformation).to receive(:describe_stack_resource)
                                  .with(stack_name: stack_name, logical_resource_id: stack_resource_name)
                                  .and_return(response)

        expect(subject.logical_resource(stack_resource_name)).to include(
                                                                   "PhysicalResourceId" => "i-am-sam",
                                                                   "ResourceType" => "green-eggs-and-ham"
                                                                 )
      end
    end
  end

  describe "#config" do
    context "when passed a config_path and params_template_file_path" do
      it "will return the results of the nested KumoKeisei::EnvironmentConfig.config" do
        expect(KumoKeisei::EnvironmentConfig).to receive(:new).with(stack_config.merge(params_template_file_path: "/#{stack_template_name}.yml.erb")).and_return(double(:environment_config, cf_params: {}, config: { :foo=> 'bar', :baz=> 'qux' }))
        expect(subject.config(stack_config)).to eq({:foo=> 'bar', :baz=>'qux'})
      end
    end

    context "when a config_path and nil for params_template_file_path" do
      let(:stack_config) {
        {
          config_path: 'config-path',
          env_name: 'non-production'
        }
      }

      it "will return the results of the nested KumoKeisei::EnvironmentConfig.config" do
        expect(KumoKeisei::EnvironmentConfig).to receive(:new).with(stack_config.merge(params_template_file_path: nil)).and_return(double(:environment_config, cf_params: {}, config: { :foo=> 'bar', :baz=> 'qux' }))
        expect(subject.config(stack_config)).to eq({:foo=> 'bar', :baz=>'qux'})
      end
    end

    context "if not given a stack_config containing a `config_path`" do
      let(:stack_config) {
        {
        }
      }
      it "will raise an error" do
        expect { described_class.new(app_name, environment_name).config(stack_config)}.to raise_error(KumoKeisei::Stack::UsageError)
      end
    end

  end

  describe "#params_template_path" do
    context "when looking for the parameter template file" do
      CFN_STACK_TEMPLATE_TO_PARAMATER_TEMPLATE = {
        '/foo/app.json' => '/foo/app.yml.erb',
        '/foo/rds.json' => '/foo/rds.yml.erb'
      }

      CFN_STACK_TEMPLATE_TO_PARAMATER_TEMPLATE.each_pair do |cfn_template, parameter_template|
        context "given #{cfn_template}" do
          let(:stack_cfntemplate_filename) { "#{cfn_template}" }
          it "uses a matching file in the form of #{parameter_template}" do
            expect(subject.params_template_path(stack_config)).to eq(File.join(Dir.pwd, parameter_template))
          end
        end
      end
    end

    context "when the parameter template file has not been passed in" do
      let(:stack_config) {
        {
          config_path: 'config-path',
          injected_config: { 'VpcId' => 'vpc-id' },
          env_name: 'non-production'
        }
      }

      it "will return nil" do
        expect(subject.params_template_path(stack_config)).to be_nil
      end
    end

  end

end
