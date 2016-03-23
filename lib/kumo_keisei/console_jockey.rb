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
  end
end
