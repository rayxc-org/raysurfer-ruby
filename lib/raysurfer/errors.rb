# frozen_string_literal: true

module Raysurfer
  class Error < StandardError
    attr_reader :status_code, :details

    def initialize(message, status_code: nil, details: nil)
      @status_code = status_code
      @details = details
      super(message)
    end
  end

  class AuthenticationError < Error; end

  class APIError < Error; end

  class CacheUnavailableError < Error; end

  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = "Rate limited", retry_after: nil, status_code: 429, details: nil)
      @retry_after = retry_after
      super(message, status_code: status_code, details: details)
    end
  end
end
