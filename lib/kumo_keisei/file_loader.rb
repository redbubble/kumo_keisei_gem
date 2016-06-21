module KumoKeisei
  class FileLoader
    def initialize(options)
      @config_dir_path = options[:config_dir_path]
    end

    def load_hash(file_name, optional = false)
      # reads a file presuming it's a yml in form of key: value, returning it as a hash
      path = file_path(file_name)
      raise unless File.exist?(path) or optional

      return {} unless  File.exist?(path)

      YAML::load(File.read(path))
    end

    def load_erb(file_name, optional = false)
      # loads a file, constructs an ERB object from it and returns the ERB object
      path = file_path(file_name)
      raise unless File.exist?(path) or optional

      ERB.new(File.read(path))
    end

    private

    def file_path(file_name)
      File.join(@config_dir_path, file_name)
    end
  end
end
