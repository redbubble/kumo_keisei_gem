module KumoKeisei
  class ConsoleJockey
    def self.flash_message(message)
      puts "\n"
      puts "###################=============================------------"
      puts message
      puts "------------=============================###################"
      puts "\n"

      $stdout.flush
    end

    def self.write_line(message)
      puts message

      $stdout.flush
    end

    def get_confirmation

      begin
        status = Timeout::timeout(CONFIRMATION_TIMEOUT) {
          # Something that should be interrupted if it takes more than 5 seconds...
          stdin.gets.chomp
        }
      rescue
        status = false
      end
      status == 'yes'
    end
  end
end
