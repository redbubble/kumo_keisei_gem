require 'spec_helper'

describe KumoKeisei::CloudFormationStack do

  let(:bash) { double('bash') }

  subject { KumoKeisei::CloudFormationStack.new(stack: "my-stack", base_template: "template.json") }

  before do
    allow(KumoKeisei::Bash).to receive(:new).and_return(bash)
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


  end

  describe "#logical_resource" do

    it "returns details for a resource" do

      expect(bash).to receive(:execute).with("aws cloudformation describe-stack-resource --stack-name=my-stack --logical-resource-id=my-resource").and_return('{"StackResourceDetail": { "key": "value"}}')

      expect(subject.logical_resource("my-resource")).to eq ({ "key" => "value"  })
    end
  end
end
