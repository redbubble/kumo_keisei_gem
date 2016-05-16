require 'spec_helper'
require 'ostruct'

describe KumoKeisei::ConsoleJockey do
  describe "#get_confirmation" do
    let(:timeout) { 0.5 }
    subject { described_class }

    context 'no timeout' do

      it 'returns true if user enters yes' do
        allow(STDIN).to receive(:gets) { 'yes'}
        expect(subject.get_confirmation(timeout)).to be true
      end

      it 'returns false if user enters anything other than yes' do
        allow(STDIN).to receive(:gets) { 'aoisdjofa'}
        expect(subject.get_confirmation).to be false
      end
    end

    context 'timeout' do
      it 'returns false if there is a timeout' do
        expect(subject.get_confirmation(timeout)).to be false
      end
    end

  end
end
