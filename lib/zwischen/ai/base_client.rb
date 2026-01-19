# frozen_string_literal: true

module Zwischen
  module AI
    class Error < StandardError; end

    class BaseClient
      attr_reader :api_key, :config

      def initialize(api_key: nil, config: {})
        @api_key = api_key
        @config = config
        validate_config!
      end

      def analyze(prompt)
        raise NotImplementedError, "#{self.class.name} must implement #analyze"
      end

      protected

      def validate_config!
        # Hook for subclasses
      end
    end
  end
end
