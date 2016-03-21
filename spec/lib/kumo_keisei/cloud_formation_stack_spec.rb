require 'spec_helper'

describe KumoKeisei::CloudFormationStack do

  let(:bash) { double('bash') }

  let(:stack_name) { "my-stack" }
  let(:stack_template) { "template.json" }
  let(:env_template) { nil }
  subject(:instance) { KumoKeisei::CloudFormationStack.new(stack_name, stack_template, env_template) }

  before do
    allow(KumoKeisei::Bash).to receive(:new).and_return(bash)
  end

  describe "#destroy" do

     it "updates the stack" do
        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "COMPLETE" }] }', "does not exist")
        expect(bash).to receive(:execute).with("aws cloudformation delete-stack --stack-name my-stack")
        subject.destroy!
    end

  end

  pending "#apply!" do

    let(:stack_exists) { true }

    before do
      allow($stdout).to receive(:puts)
      allow(bash).to receive(:exit_status_for).with("aws cloudformation describe-stack-resources --stack-name my-stack").and_return(stack_exists ? 0 : 1)
    end

    context "when specifying params" do

      before do
        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "COMPLETE" }] }')
      end

      context "dynamic parameters" do

        it "passes parameters" do
          expect(bash).to receive(:execute).with('aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json --parameters \[\{\"ParameterKey\":\"testDynamicKey\",\"ParameterValue\":\"testValue\"\}\]')
          subject.apply!(testDynamicKey: 'testValue')
        end
      end

      context "file params" do

        let(:params_file_content) {
          [
            {
              "ParameterKey" => "testFileKey",
              "ParameterValue" => "testFileValue",
            },
          ]
        }
        let(:params_file_name) { "params.json"  }
        let(:env_template) { params_file_name }

        before do
          allow(File).to receive(:exist?).with(params_file_name).and_return(true)
          allow(File).to receive(:read).with(params_file_name).and_return(params_file_content.to_json)
        end

        it "passes parameters" do
          expect(bash).to receive(:execute).with('aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json --parameters \[\{\"ParameterKey\":\"testFileKey\",\"ParameterValue\":\"testFileValue\"\}\]')
          subject.apply!
        end

        context "and dynamic params" do

          it "passes all parameters" do
            expect(bash).to receive(:execute).with('aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json --parameters \[\{\"ParameterKey\":\"testFileKey\",\"ParameterValue\":\"testFileValue\"\},\{\"ParameterKey\":\"testDynamicKey\",\"ParameterValue\":\"testDynamicValue\"\}\]')
            subject.apply!(testDynamicKey: 'testDynamicValue')
          end

          it 'overrides file params' do
            expect(bash).to receive(:execute).with('aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json --parameters \[\{\"ParameterKey\":\"testFileKey\",\"ParameterValue\":\"testDynamicValue\"\}\]')
            subject.apply!(testFileKey: 'testDynamicValue')
          end
        end

        context "list in params" do
          let(:params_file_content) {
            [
              {
                "ParameterKey" => "testFileKey",
                "ParameterValue" => "testFileValue1,testFileValue2",
              },
            ]
          }

          it "passes escaped parameters" do
            expect(bash).to receive(:execute).with('aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json --parameters \[\{\"ParameterKey\":\"testFileKey\",\"ParameterValue\":\"testFileValue1,testFileValue2\"\}\]')
            subject.apply!
          end
        end
      end
    end

    context "stack is updatable" do

      ['UPDATE_ROLLBACK_COMPLETE', 'CREATE_COMPLETE', 'UPDATE_COMPLETE', 'DELETE_COMPLETE'].each do |stack_status| 
        it "updates the stack when in #{stack_status} status" do
          allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return(
            %Q({"Stacks": [{ "StackStatus": "#{stack_status}" }] }),
            '{"Stacks": [{ "StackStatus": "UPDATE_COMPLETE" }] }'
          )
          expect(bash).to receive(:execute).with("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json")
          subject.apply!
        end
      end

      context "when the update is unsuccessful" do

        before :each do
          allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "UPDATE_COMPLETE" }] }')
        end

        context 'and it was due to there being no updates to be performed' do

          before do
            allow(bash).to receive(:execute).with("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json").and_yield("No updates are to be performed", 123)
          end

          it 'says no updates are to be performed' do
            expect($stdout).to receive(:puts).with('No updates are to be performed')
            subject.apply!
          end

          it "continues on" do
            expect { subject.apply! }.to_not raise_error
          end
        end

        context "for an unknown reason" do

          before do
            allow(bash).to receive(:execute).with("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json").and_yield("Error! Error!", 123)
          end

          it "outputs the command response" do
            expect($stdout).to receive(:puts).with('Error! Error!')
            expect { subject.apply! }.to raise_error KumoKeisei::CloudFormationStack::AwsCliError
          end

          it "raises an error" do
            expect { subject.apply! }.to raise_error KumoKeisei::CloudFormationStack::AwsCliError
          end
        end
      end
    end

    context "stack is not updatable" do

      let(:stack_exists) { false }

      context "the stack does not exist" do
        let(:stack_name) { "my-stack" }

        it "creates the stack" do
          allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name #{stack_name}").and_return("A client error (ValidationError) occurred when calling the DescribeStacks operation: Stack with id #{stack_name} does not exist")
          expect(bash).to receive(:execute).with("aws cloudformation create-stack --capabilities CAPABILITY_IAM --stack-name #{stack_name} --template-body file://template.json")
          subject.apply!
        end
      end

      context "the stack is in ROLLBACK_COMPLETE, or ROLLBACK_FAILED" do
        it "deletes the dead stack and creates a new one" do
          cloudformation = instance_double(Aws::CloudFormation::Client)
          allow(Aws::CloudFormation::Client).to receive(:new).and_return(cloudformation)

          stack = double(stack_name: stack_name, stack_status: "ROLLBACK_COMPLETE")
          allow(cloudformation).to receive(:describe_stacks).and_return([stack])

          expect(cloudformation).to receive(:delete_stack).with(stack_name: stack_name)
          expect(cloudformation).to receive(:create_stack)

          allow(cloudformation).to receive(:wait_until).with(:stack_delete_complete, stack_name: stack_name).and_return(nil)
          allow(cloudformation).to receive(:wait_until).with(:stack_create_complete, stack_name: stack_name).and_return(nil)

          subject.apply!
        end
      end

      context "the stack in in UPDATE_ROLLBACK_FAILED" do
        it "should blow up" do

        end
      end
    end
  end

  describe "#logical_resource" do

    it "returns details for a resource" do

      expect(bash).to receive(:execute).with("aws cloudformation describe-stack-resource --stack-name=my-stack --logical-resource-id=my-resource").and_return('{"StackResourceDetail": { "key": "value"}}')

      expect(subject.logical_resource("my-resource")).to eq ({ "key" => "value"  })
    end
  end

  describe "#outputs" do

    it "returns outputs for a stack" do

      expect(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name=my-stack").and_return('{ "Stacks": [ { "Outputs": [ { "OutputKey": "MyKey", "OutputValue": "MyValue" }] } ] }')

      expect(subject.outputs("MyKey")).to eq ("MyValue")
    end
  end

  describe "fetch_param" do

    subject { instance.fetch_param(key) }

    before do
      allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name=my-stack").and_return(stack_description)
    end

    context "when given a param key" do

      let(:key) { "known_key" }

      context "when the stack has a parameter for the given key" do

        let(:stack_description) do
          { "Stacks" => [
              {
                "Parameters" => [ {"ParameterKey" => "known_key", "ParameterValue" => "superman"} ]
              }
          ] }.to_json
        end

        it "returns the parameter value" do
          expect(subject).to eq "superman"
        end
      end

      context "when the stack doesn't have a parameter for the given key" do

        let(:key) { "unknown_key" }

        let(:stack_description) do
          { "Stacks" => [
              {
                "Parameters" => [ {"ParameterKey" => "some_other_key", "ParameterValue" => "superman"} ]
              }
          ] }.to_json
        end

        it "returns nil" do
          expect(subject).to eq nil
        end
      end

      context "when the reponse from aws is in an unexpected format" do

        let(:key) { "anything" }

        let(:stack_description) do
          { "Any key except for Stacks" => [
              { "Parameters" => [ {"ParameterKey" => "some_other_key", "ParameterValue" => "superman"} ] }
          ] }.to_json
        end

        it "raises a helpful error" do
          expect{subject}.to raise_error KumoKeisei::CloudFormationStack::ParseError, "Could not parse response from AWS: #{stack_description}"
        end
      end
    end
  end
end
