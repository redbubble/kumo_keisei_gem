require 'json'

module KumoKeisei
  class CfnParameterBuilder
    def initialize(dynamic_params = {})
      @dynamic_params = dynamic_params
    end

    def params
      @dynamic_params.map do |key, value|
        {
          parameter_key: key.to_s,
          parameter_value: value
        }
      end
    end
  end

  class CfnJsonFileLoader
    def initialize(file_path)
      @file_path = file_path
    end

    def load_config!
      file_contents = JSON.parse(File.read(@file_path))

      file_contents.inject({}) do |acc, param| 
        acc.merge(param['ParameterKey'] => param['ParameterValue'])
      end
    end

    def load_config
      return {} unless (@file_path && File.exists?(@file_path))
      load_config!
    end
  end
end
