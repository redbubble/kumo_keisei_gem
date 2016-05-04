require 'spec_helper'

describe KumoKeisei::EnvironmentConfig do
  describe '#cf_params' do

    let(:env_name) { 'the_jungle' }
    let(:config_dir_path) { '/var/config' }
    let(:options) do
      {
        env_name: env_name,
        config_dir_path: config_dir_path
      }
    end

    before do
      allow(File).to receive(:read).and_return(parameter_template)
    end

    subject { described_class.new(options).cf_params }

    context 'no params' do
      let(:parameter_template) { '' }

      it 'creates an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'a hard-coded param' do
      let(:parameter_template) { "parameter_key: <%= 'parameter_value' %>" }

      it 'creates a array containing an aws formatted parameter hash' do
        expect(subject).to eq([{parameter_key: "parameter_key", parameter_value: "parameter_value"}])
      end
    end

    context 'a templated param' do
      let(:parameter_template) { "stack_name: <%= config['stack_name'] %>" }
      let(:environment_config_file_path) { "#{config_dir_path}/#{env_name}.yml" }
      let(:environment_parameter_file) { "stack_name: 'okonomiyaki'"}

      it 'creates a array containing an aws formatted parameter hash' do
        allow(File).to receive(:exist?)
          .with("/var/config/common.yml")
          .and_return(false)

        allow(File).to receive(:exist?)
          .with(environment_config_file_path)
          .and_return(true)

        allow(File).to receive(:read)
          .with(environment_config_file_path)
          .and_return(environment_parameter_file)

        expect(subject).to eq([{parameter_key: "stack_name", parameter_value: "okonomiyaki"}])
      end
    end

    #TODO: Deal with common config merging
    #TODO: Deal with secrets
  end
end
