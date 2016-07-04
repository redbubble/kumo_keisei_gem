require 'spec_helper'

describe KumoKeisei::EnvironmentConfig do
  let(:env_name) { 'the_jungle' }
  let(:config_dir_path) { '/var/config' }
  let(:options) do
    {
      env_name: env_name,
      config_dir_path: config_dir_path,
      params_template_file_path: params_template_file_path
    }
  end
  let(:file_loader) { instance_double(KumoKeisei::FileLoader) }
  let(:file_loader_cloudformation) { instance_double(KumoKeisei::FileLoader) }
  let(:parameters) { ERB.new("") }
  let(:params_template_file_path) { 'junk.txt' }
  let(:environment_config_file_name) { "#{env_name}.yml" }
  let(:kms) { instance_double(KumoKi::KMS) }
  let(:logger) { double(:test_logger, debug: nil) }
  let(:environment_config) { described_class.new(options, logger) }

  before do
    allow(KumoKeisei::FileLoader).to receive(:new).and_return(file_loader)
    allow(KumoKi::KMS).to receive(:new).and_return(kms)
    allow(file_loader).to receive(:load_erb).with(params_template_file_path).and_return(parameters)
    allow(File).to receive(:dirname).and_return('/tmp')
  end

  context 'backward compatibility' do
      context 'config_path' do
        let(:options) do
          {
            env_name: env_name,
            config_path: config_dir_path
          }
        end
        it 'will be used without complaint' do
            expect(KumoKeisei::FileLoader).to receive(:new).with(config_dir_path: config_dir_path).and_return(nil)
            described_class.new(options)
        end
      end

      context 'config_dir_path' do
        let(:options) do
          {
            env_name: env_name,
            config_dir_path: config_dir_path
          }
        end

        before do
          @orig_stderr = $stderr
          $stderr = StringIO.new
        end

        after do
          $stderr = @orig_stderr
        end

        it 'will be used if given and raise a deprecation warning' do
            expect(KumoKeisei::FileLoader).to receive(:new).with(config_dir_path: config_dir_path).and_return(nil)
            described_class.new(options)
            $stderr.rewind
            expect($stderr.string.chomp).to eq("[DEPRECATION] `:config_dir_path` is deprecated, please pass in `:config_path` instead")
        end
      end

      context 'neither config_path nor config_dir_path' do
        let(:options) do
          {
            env_name: env_name
          }
        end

        it 'will raise an error' do
          expect { described_class.new(options)}.to raise_error(KumoKeisei::EnvironmentConfig::ConfigurationError)
        end
      end
  end

  context 'unit tests' do
    let(:fake_environment_binding) { binding }

    describe '#get_binding' do
      subject { environment_config.get_binding }

      it 'returns a binding' do
        expect(subject).to be_a(Binding)
      end
    end

    describe '#cf_params' do
      subject { environment_config.cf_params }

      context 'params template file path is not provided' do
        let(:options) do
          {
            env_name: env_name,
            config_dir_path: config_dir_path
          }
        end

        it 'creates an empty array' do
          expect(subject).to eq([])
        end
      end

      context 'params is empty' do
        let(:parameters) { nil }

        it 'creates an empty array' do
          expect(subject).to eq([])
        end
      end

      context 'a hard-coded param' do
        let(:parameters) { ERB.new("stack_name: \"foo-stack\"") }
        let(:parameters) { ERB.new("parameter_key: \"parameter_value\"") }

        before do
          allow(file_loader).to receive(:load_hash).with('common.yml').and_return({})
          allow(file_loader).to receive(:load_hash).with('the_jungle.yml').and_return({})
          allow(file_loader).to receive(:load_hash).with('development.yml').and_return({})
        end

        it 'creates a array containing an aws formatted parameter hash' do
          expect(subject).to eq([{parameter_key: "parameter_key", parameter_value: "parameter_value"}])
        end
      end

      describe "#config" do
        subject { described_class.new(options, logger).config }

        context 'injected config' do

          let(:options) do
            {
              env_name: env_name,
              config_dir_path: config_dir_path,
              params_template_file_path: params_template_file_path,
              injected_config: { "injected" => "yes" }
            }
          end

          let(:common_parameters) { { "stack_name" => "okonomiyaki" } }
          it 'adds injected config to the config hash' do
            expect(file_loader).to receive(:load_hash).with('common.yml').and_return(common_parameters)
            expect(file_loader).to receive(:load_hash).with(environment_config_file_name).and_return({})
            expect(file_loader).to receive(:load_hash).with("development.yml").and_return({})

            expect(subject).to eq({ "stack_name" => "okonomiyaki", "injected" => "yes" })
          end
        end

        context 'common config' do
          let(:common_parameters) { { "stack_name" => "okonomiyaki" } }

          it 'creates a array containing an aws formatted parameter hash' do
            expect(file_loader).to receive(:load_hash).with('common.yml').and_return(common_parameters)
            expect(file_loader).to receive(:load_hash).with(environment_config_file_name).and_return({})
            expect(file_loader).to receive(:load_hash).with("development.yml").and_return({})

            expect(subject).to eq('stack_name' => 'okonomiyaki')
          end
        end

        context 'merging common and environment specific configurations' do
          let(:environment_config) { {'image' => 'ami-5678'} }
          let(:development_config) { {'image' => 'ami-9999'} }

          context 'with environmental overrides' do
            let(:parameter_template) { "image: <%= config['image'] %>" }
            let(:common_config) { {'image' => 'ami-1234'} }
            let(:env_name) { 'development' }

            it 'replaces the common value with the env value' do
              expect(file_loader).to receive(:load_hash).with('common.yml').and_return(common_config)
              expect(file_loader).to receive(:load_hash).with(environment_config_file_name).and_return(environment_config)
              expect(subject).to eq('image' => 'ami-5678')
            end
          end

          it 'falls back to a default environment if the requested one does not exist' do
            expect(file_loader).to receive(:load_hash).with('common.yml').and_return({})
            expect(file_loader).to receive(:load_hash).with("#{env_name}.yml").and_return({})
            expect(file_loader).to receive(:load_hash).with("development.yml").and_return(development_config)

            expect(subject).to eq('image' => 'ami-9999')
          end
        end
      end

      describe "#plain_text_secrets" do
        subject { described_class.new(options, logger).plain_text_secrets }

        let(:crypted_password) { 'lookatmyencryptedpasswords' }
        let(:plain_text_password) { 'plain_text_password' }
        let(:secrets) { { 'secret_password' => "[ENC,#{crypted_password}" } }

        let(:crypted_env_password) { 'cryptedenvpassword' }
        let(:plain_text_env_password) { 'plain_text_env_password' }
        let(:env_secrets) { { 'secret_password' => "[ENC,#{crypted_env_password}"}}

        before do
          allow(kms).to receive(:decrypt).with(crypted_password).and_return(plain_text_password)
        end

        it 'decrypts common secrets' do
          allow(file_loader).to receive(:load_hash).with('common_secrets.yml').and_return(secrets)
          allow(file_loader).to receive(:load_hash).with("#{env_name}_secrets.yml").and_return({})
          allow(file_loader).to receive(:load_hash).with("development_secrets.yml").and_return({})

          expect(subject).to eq('secret_password' => plain_text_password)
        end

        it 'decrypts environment secrets' do
          allow(file_loader).to receive(:load_hash).with('common_secrets.yml').and_return({})
          allow(file_loader).to receive(:load_hash).with("#{env_name}_secrets.yml").and_return(secrets)

          expect(subject).to eq('secret_password' => plain_text_password)
        end

        it 'gives preference to environment secrets' do
          allow(file_loader).to receive(:load_hash).with('common_secrets.yml').and_return(secrets)
          allow(file_loader).to receive(:load_hash).with("#{env_name}_secrets.yml").and_return(env_secrets)
          allow(kms).to receive(:decrypt).with(crypted_env_password).and_return(plain_text_env_password)

          expect(subject).to eq('secret_password' => plain_text_env_password)
        end

        it 'falls back to a default environment if the requested one does not exist' do
          allow(file_loader).to receive(:load_hash).with('common_secrets.yml').and_return({})
          allow(file_loader).to receive(:load_hash).with("#{env_name}_secrets.yml").and_return({})
          expect(file_loader).to receive(:load_hash).with("development_secrets.yml").and_return(secrets)

          expect(subject).to eq('secret_password' => plain_text_password)
        end
      end

      describe '#development?' do
        %w(production staging).each do |environment|
          it "returns false for #{environment}" do
            expect(
              described_class.new({
                env_name: environment,
                config_dir_path: '',
                params_template_file_path: ''}
              ).development?).to eq false
          end
        end

        it 'returns true for anything other than production or staging' do
          expect(
            described_class.new({
              env_name: 'fred',
              config_dir_path: '',
              params_template_file_path: ''}
            ).development?).to eq true
        end
      end
    end

    context 'integration tests' do
      describe '#cf_params' do
        subject { environment_config.cf_params }

        context 'templated params' do
          let(:parameters) { ERB.new("stack_name: \"<%= config['stack_name'] %>\"" ) }
          let(:common_config) { { "stack_name" => "common"} }
          let(:staging_config) { { "stack_name" => "staging" } }
          let(:development_config) { { "stack_name" => "development" } }

          context 'hiearchy of parameters' do
            it 'will load values from the common paramater file' do
              expect(file_loader).to receive(:load_hash).with('common.yml').and_return(common_config)
              expect(file_loader).to receive(:load_hash).with("development.yml").and_return({})
              expect(file_loader).to receive(:load_hash).with(environment_config_file_name).and_return({})
              expect(subject).to eq([{parameter_key: "stack_name", parameter_value: "common"}])
            end

            it 'will load values from the environment specific file' do
              expect(file_loader).to receive(:load_hash).with('common.yml').and_return({})
              expect(file_loader).to receive(:load_hash).with(environment_config_file_name).and_return(staging_config)
              expect(subject).to eq([{parameter_key: "stack_name", parameter_value: "staging"}])
            end

            it 'will load values from the shared development file if an environment specific file has no values' do
              expect(file_loader).to receive(:load_hash).with('common.yml').and_return({})
              expect(file_loader).to receive(:load_hash).with(environment_config_file_name).and_return({})
              expect(file_loader).to receive(:load_hash).with("development.yml").and_return(development_config)
              expect(subject).to eq([{parameter_key: "stack_name", parameter_value: "development"}])
            end
          end
        end
      end
    end
  end
end
