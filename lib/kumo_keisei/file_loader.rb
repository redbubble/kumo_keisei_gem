require 'erb'

module KumoKeisei
  class FileLoader
    def initialize(options)
      @config_dir_path = options[:config_dir_path]
    end

    def load_hash(file_name, optional = true)
      # reads a file presuming it's a yml in form of key: value, returning it as a hash
      path = file_path(file_name)

      begin
        YAML::load(File.read(path))
      rescue Errno::ENOENT => ex
        # file not found, return empty dictionary if that is ok
        return {} if optional
        raise ex
      rescue StandardError => ex
        # this is an error we weren't expecting
        raise ex
      end
    end

    def load_erb(file_name)
      # loads a file, constructs an ERB object from it and returns the ERB object
      # DOES NOT RENDER A RESULT!!
      path = file_path(file_name)
      ERB.new(File.read(path))
    end

    private

    def file_path(file_name)
      File.join(@config_dir_path, file_name)
    end
  end
end
