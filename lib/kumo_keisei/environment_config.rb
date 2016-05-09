require 'kumo_ki'
require 'logger'
require 'yaml'

require_relative 'file_loader'
require_relative 'parameter_builder'

class KumoKeisei::EnvironmentConfig
  LOGGER = Logger.new(STDOUT)

  attr_reader :app_name, :env_name

  def initialize(options, logger = LOGGER)
    @app_name = options[:app_name]
    @env_name = options[:env_name]
    @config_dir_path = options[:config_dir_path]
    @params_template_file_path = options[:params_template_file_path]
    @injected_config = options[:injected_config] || {}
    @file_loader = KumoKeisei::FileLoader.new(options)

    @log = logger
  end

  def get_binding
    binding
  end

  def production?
    env_name == "production"
  end

  def development?
    !(%w(production staging).include?(env_name))
  end

  def plain_text_secrets
    @plain_text_secrets ||= decrypt_secrets(encrypted_secrets)
  end

  def config
    @config ||= common_config.merge(env_config).merge(@injected_config)
  end

  def cf_params
    return [] unless params_template
    KumoKeisei::ParameterBuilder.new(get_stack_params(params_template)).params
  end

  private

  def kms
    @kms ||= KumoKi::KMS.new
  end

  def get_stack_params(params_template)
    YAML.load(ERB.new(params_template).result(get_binding))
  end

  def params_template
    return nil unless @params_template_file_path

    @file_loader.load_config!(@params_template_file_path)
  end

  def decrypt_secrets(secrets)
    Hash[
      secrets.map do |name, cipher_text|
        @log.debug "Decrypting '#{name}'"
        if cipher_text.start_with? '[ENC,'
          begin
            [name, "#{kms.decrypt cipher_text[5,cipher_text.size]}"]
          rescue
            @log.error "Error decrypting secret '#{name}'"
            raise
          end
        else
          [name, cipher_text]
        end
      end
    ]
  end

  def env_config_file_name
    "#{env_name}.yml"
  end

  def env_secrets_file_name
    "#{env_name}_secrets.yml"
  end

  def encrypted_secrets
    encrypted_common_secrets.merge(encrypted_env_secrets)
  end

  def encrypted_common_secrets
    @file_loader.load_config('common_secrets.yml')
  end

  def encrypted_env_secrets
    @file_loader.load_config(env_secrets_file_name)
  end

  def common_config
    @file_loader.load_config('common.yml')
  end

  def env_config
    @file_loader.load_config(env_config_file_name)
  end
end
