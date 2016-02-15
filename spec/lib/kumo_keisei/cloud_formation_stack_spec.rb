require 'spec_helper'

describe KumoKeisei::CloudFormationStack do

  let(:bash) { double('bash') }

  let(:stack_name) { "my-stack" }
  let(:stack_template) { "template.json" }
  let(:env_template) { nil }
  subject { KumoKeisei::CloudFormationStack.new(stack_name, stack_template, env_template) }

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

  describe "#apply!" do

    before do
      allow($stdout).to receive(:puts)
      allow(bash).to receive(:exit_status_for).with("aws cloudformation describe-stack-resources --stack-name my-stack").and_return(stack_exists ? 0 : 1)
    end

    context "stack exists" do

      let(:stack_exists) { true }

      before do
        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "COMPLETE" }] }')
      end

      it "updates the stack" do
        expect(bash).to receive(:execute).with("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json")
        subject.apply!
      end

      context "stack starts with UPDATE_ROLLBACK_COMPLETE status" do

        before do
          allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return(
            '{"Stacks": [{ "StackStatus": "UPDATE_ROLLBACK_COMPLETE" }] }',
            '{"Stacks": [{ "StackStatus": "UPDATE_COMPLETE" }] }',
          )
        end

        it "updates the stack" do
          expect(bash).to receive(:execute).with("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json")
          subject.apply!
        end
      end

      context "when specifying params" do

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

      context "when the command is unsuccessful" do

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

    context "stack doesn't exist" do

      let(:stack_exists) { false }

      it "creates the stack" do
        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "COMPLETE" }] }')
        expect(bash).to receive(:execute).with("aws cloudformation create-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json")
        subject.apply!
      end
    end

    context "rollback" do

      let(:stack_exists) { true }
      let(:stack_status) { 'ROLLBACK_COMPLETE' }

      before do
        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "'+stack_status+'" }] }')
        allow(bash).to receive(:execute).with("aws cloudformation update-stack --capabilities CAPABILITY_IAM --stack-name my-stack --template-body file://template.json")
      end

      it "raises exception" do
        expect { subject.apply! }.to raise_error StandardError
      end


      context "rollback failed" do

        let(:stack_status) { 'ROLLBACK_FAILED' }

        it "raises exception" do
          expect { subject.apply! }.to raise_error StandardError
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
end
