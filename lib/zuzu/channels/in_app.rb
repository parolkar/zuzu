# frozen_string_literal: true

module Zuzu
  module Channels
    # The desktop GUI itself is the in-app channel. This is a no-op marker.
    class InApp < Base
      def start = @running = true
      def stop  = @running = false
    end
  end
end
