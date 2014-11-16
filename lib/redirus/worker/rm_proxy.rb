module Redirus
  module Worker
    class RmProxy < Proxy
      include Redirus::Utils

      def perform_action(name, type)
        File.delete(config_file_path(name, type))
      end
    end
  end
end