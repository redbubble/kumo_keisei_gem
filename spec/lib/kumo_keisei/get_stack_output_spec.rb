describe KumoKeisei::GetStackOutput do
  describe "#output" do
    let(:aws_stack) { double(:stack, outputs: [output])}
    let(:name) { "Key" }
    subject { described_class.new(aws_stack).output(name) }

    context 'when the stack exists' do
      let(:value) { "Value" }
      let(:output_key) { name }
      let(:output) { double(:output, output_key: output_key, output_value: value) }

      it "returns the outputs given by CloudFormation" do
        expect(subject).to eq(value)
      end

      context "Output key doesn't exist" do
        let(:output_key) { "something else" }

        it "returns the outputs given by CloudFormation" do
          expect(subject).to be_nil
        end
      end
    end

    context 'when the stack does not exist' do
      let(:aws_stack) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end
end
