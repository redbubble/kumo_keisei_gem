module KumoKeisei
  class Bash

    def execute(command)
      puts "Executing --> #{command}"
      output = `#{command} 2>&1`.strip
      status = $?.exitstatus
      if block_given?
        yield(output, status)
      end
      output
    end

    def exit_status_for(command)
      `#{command}`
      $?.exitstatus
    end

  end
end
