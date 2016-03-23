require 'spec_helper'
require 'ostruct'

describe KumoKeisei::CloudFormationStack do

  def stack_result_list_with_status(status)
    stack = OpenStruct.new(stack_status: status)
    OpenStruct.new(stacks: [stack])
  end

  let(:stack_name) { "my-stack" }
  let(:stack_template_path) { "template.json" }
  let(:file_params_path) { nil }
  let(:cloudformation) { instance_double(Aws::CloudFormation::Client) }
  let(:happy_stack_status) { "CREATE_COMPLETE" }
  let(:cf_stack) { stack_result_list_with_status(happy_stack_status) }
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

  subject(:instance) { KumoKeisei::CloudFormationStack.new(stack_name, stack_template_path, file_params_path) }

  before do
    allow(KumoKeisei::ConsoleJockey).to receive(:flash_message)
    allow(Aws::CloudFormation::Client).to receive(:new).and_return(cloudformation)
    allow(cloudformation).to receive(:describe_stacks).with({stack_name: stack_name}).and_return(cf_stack)
    allow(KumoKeisei::ParameterBuilder).to receive(:new).and_return(parameter_builder)
    allow(File).to receive(:read).with(stack_template_path).and_return(stack_template_body)
  end

  describe "#destroy" do

     it "deletes the stack" do
       expect(cloudformation).to receive(:delete_stack).with({stack_name: stack_name}).and_return(cf_stack)
       allow(cloudformation).to receive(:wait_until).with(:stack_delete_complete, stack_name: stack_name).and_return(nil)

       subject.destroy!
    end

  end

  describe "#apply!" do
    context "when the stack is updatable" do
      UPDATEABLE_STATUSES = ['UPDATE_ROLLBACK_COMPLETE', 'CREATE_COMPLETE', 'UPDATE_COMPLETE', 'DELETE_COMPLETE']

      context "when the stack has changed" do
        before do
          allow(cloudformation).to receive(:wait_until).with(:stack_update_complete, stack_name: stack_name).and_return(nil)
        end

        UPDATEABLE_STATUSES.each do |stack_status|
          it "updates the stack when in #{stack_status} status" do
            allow(cloudformation).to receive(:describe_stacks).with({stack_name: stack_name}).and_return(
              stack_result_list_with_status(stack_status),
              stack_result_list_with_status("UPDATE_COMPLETE")
            )
            expect(cloudformation).to receive(:update_stack).with(cf_stack_update_params).and_return("stack_id")
            subject.apply!
          end
        end
      end

      context "when the stack has not changed" do
        let(:error) { Aws::CloudFormation::Errors::ValidationError.new('', 'No updates are to be performed.') }

        UPDATEABLE_STATUSES.each do |stack_status|
          it "reports that nothing has changed when in #{stack_status} status" do
            allow(cloudformation).to receive(:describe_stacks)
              .with({stack_name: stack_name})
              .and_return(stack_result_list_with_status(stack_status))

            expect(cloudformation).to receive(:update_stack).with(cf_stack_update_params).and_raise(error)
            expect(KumoKeisei::ConsoleJockey).to receive(:flash_message).with(/No changes need to be applied/)

            subject.apply!
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

      context "and the stack does not exist" do
        let(:stack_name) { "my-stack" }

        it "creates the stack" do
          allow(cloudformation).to receive(:delete_stack)
          allow(cloudformation).to receive(:describe_stacks).with(stack_name: stack_name).and_raise(Aws::CloudFormation::Errors::ValidationError.new('',''))
          expect(cloudformation).to receive(:create_stack).with(cf_stack_create_params)
          subject.apply!
        end
      end

      context "and the stack is in ROLLBACK_COMPLETE, or ROLLBACK_FAILED" do
        it "deletes the dead stack and creates a new one" do
          allow(cloudformation).to receive(:describe_stacks).and_return(stack_result_list_with_status("ROLLBACK_COMPLETE"))

          expect(cloudformation).to receive(:delete_stack).with(stack_name: stack_name)
          expect(cloudformation).to receive(:create_stack)

          allow(cloudformation).to receive(:wait_until).with(:stack_create_complete, stack_name: stack_name).and_return(nil)

          subject.apply!
        end
      end

      context "and the stack in in UPDATE_ROLLBACK_FAILED" do
        it "should blow up" do
          allow(cloudformation).to receive(:describe_stacks).and_return(stack_result_list_with_status("UPDATE_ROLLBACK_FAILED"))

          expect { subject.apply! }.to raise_error("Stack is in an unrecoverable state")
        end
      end

      context "and the stack is busy" do
        it "should blow up" do
          allow(cloudformation).to receive(:describe_stacks).and_return(stack_result_list_with_status("UPDATE_IN_PROGRESS"))

          expect { subject.apply! }.to raise_error("Stack is busy, try again soon")
        end
      end
    end
  end
end
