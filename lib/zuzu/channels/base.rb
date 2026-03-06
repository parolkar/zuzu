# frozen_string_literal: true

module Zuzu
  module Channels
    # Abstract base class for message channels.
    class Base
      def initialize(agent)
        @agent   = agent
        @running = false
      end

      def start   = raise(NotImplementedError)
      def stop    = raise(NotImplementedError)
      def running? = @running

      def handle(message)
        @agent.process(message)
      end
    end
  end
end
