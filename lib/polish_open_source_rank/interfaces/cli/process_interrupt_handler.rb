# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      module ProcessInterruptHandler
        INTERRUPT_SIGNALS = %w[INT TERM].freeze

        def self.call(error_class:)
          previous_handlers = install(error_class)
          yield
        ensure
          restore(previous_handlers) if previous_handlers
        end

        def self.install(error_class)
          main_thread = Thread.main
          INTERRUPT_SIGNALS.to_h do |signal|
            previous = Signal.trap(signal) do
              main_thread.raise error_class, "Received SIG#{signal}"
            end
            [signal, previous]
          end
        end
        private_class_method :install

        def self.restore(previous_handlers)
          previous_handlers.each { |signal, handler| Signal.trap(signal, handler) }
        end
        private_class_method :restore
      end
    end
  end
end
