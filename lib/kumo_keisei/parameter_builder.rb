require 'json'

module KumoKeisei
  class ParameterBuilder
    def initialize(dynamic_params = {}, file_path = nil)
      @dynamic_params = dynamic_params
      @file_path = file_path
    end

    def params
      parsed_dynamic_params + parsed_file_params
    end

    def parsed_dynamic_params
      @dynamic_params.map do |key, value|
        {
          parameter_key: key.to_s,
          parameter_value: value
        }
      end
    end

    def parsed_file_params
      return [] unless (@file_path && File.exist?(@file_path))

      file_contents = JSON.parse(File.read(@file_path))

      file_contents.map do |param|
        {
          parameter_key: param["ParameterKey"],
          parameter_value: param["ParameterValue"]
        }
      end
    end
  end
end
