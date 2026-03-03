# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module Raysurfer
  class Client
    DEFAULT_BASE_URL = "https://api.raysurfer.com"
    DEFAULT_TIMEOUT_SECONDS = 60
    MAX_RETRIES = 3
    RETRY_BASE_DELAY_SECONDS = 0.5
    RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504].freeze

    attr_reader :api_key, :base_url, :timeout, :organization_id, :workspace_id, :snips_desired, :public_snips, :agent_id

    def initialize(
      api_key: ENV["RAYSURFER_API_KEY"],
      base_url: DEFAULT_BASE_URL,
      timeout: DEFAULT_TIMEOUT_SECONDS,
      organization_id: nil,
      workspace_id: nil,
      snips_desired: nil,
      public_snips: false,
      agent_id: nil
    )
      ensure_valid_url!(base_url)
      ensure_positive_number!(timeout, "timeout")
      ensure_valid_snips_desired!(snips_desired)

      @api_key = api_key
      @base_url = base_url.chomp("/")
      @timeout = timeout.to_f
      @organization_id = organization_id
      @workspace_id = workspace_id
      @snips_desired = snips_desired
      @public_snips = public_snips
      @agent_id = agent_id
    end

    def search(
      task:,
      top_k: 5,
      min_verdict_score: 0.3,
      min_human_upvotes: 0,
      prefer_complete: false,
      input_schema: nil,
      workspace_id: nil,
      per_function_reputation: false
    )
      ensure_non_empty_string!(task, "task")

      payload = {
        task: task,
        top_k: Integer(top_k),
        min_verdict_score: Float(min_verdict_score),
        min_human_upvotes: Integer(min_human_upvotes),
        prefer_complete: !!prefer_complete,
        input_schema: input_schema
      }
      payload[:per_function_reputation] = true if per_function_reputation

      request("POST", "/api/retrieve/search", body: payload, headers: workspace_headers(workspace_id))
    end

    def store_code_block(
      name:,
      source:,
      entrypoint:,
      language:,
      description: "",
      input_schema: {},
      output_schema: {},
      language_version: nil,
      dependencies: {},
      tags: [],
      capabilities: [],
      example_queries: nil
    )
      ensure_non_empty_string!(name, "name")
      ensure_non_empty_string!(source, "source")
      ensure_non_empty_string!(entrypoint, "entrypoint")
      ensure_non_empty_string!(language, "language")

      payload = {
        name: name,
        description: description.to_s,
        source: source,
        entrypoint: entrypoint,
        language: language,
        input_schema: input_schema || {},
        output_schema: output_schema || {},
        language_version: language_version,
        dependencies: dependencies || {},
        tags: tags || [],
        capabilities: capabilities || [],
        example_queries: example_queries
      }

      request("POST", "/api/store/code-block", body: payload)
    end

    def upload(
      task:,
      file_written:,
      succeeded:,
      cached_code_blocks: nil,
      use_raysurfer_ai_voting: true,
      user_vote: nil,
      execution_logs: nil,
      run_url: nil,
      workspace_id: nil,
      dependencies: nil,
      vote_source: nil,
      vote_count: nil,
      per_function_reputation: false
    )
      ensure_non_empty_string!(task, "task")
      normalized_file = normalize_file_written!(file_written)

      payload = {
        task: task,
        file_written: normalized_file,
        succeeded: !!succeeded,
        cached_code_blocks: cached_code_blocks,
        use_raysurfer_ai_voting: !!use_raysurfer_ai_voting,
        user_vote: user_vote,
        execution_logs: execution_logs,
        run_url: run_url,
        dependencies: dependencies,
        vote_source: vote_source,
        vote_count: vote_count
      }
      payload[:per_function_reputation] = true if per_function_reputation

      request("POST", "/api/store/execution-result", body: payload, headers: workspace_headers(workspace_id))
    end

    def upload_new_code_snip(**kwargs)
      upload(**kwargs)
    end

    def vote_code_snip(task:, code_block_id:, code_block_name:, code_block_description:, succeeded:)
      ensure_non_empty_string!(task, "task")
      ensure_non_empty_string!(code_block_id, "code_block_id")
      ensure_non_empty_string!(code_block_name, "code_block_name")
      ensure_non_empty_string!(code_block_description, "code_block_description")

      payload = {
        task: task,
        code_block_id: code_block_id,
        code_block_name: code_block_name,
        code_block_description: code_block_description,
        succeeded: !!succeeded
      }

      request("POST", "/api/store/cache-usage", body: payload)
    end

    private

    def request(method, path, body: nil, headers: nil)
      uri = URI.parse("#{@base_url}#{path}")
      attempt = 0

      loop do
        begin
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = @timeout
          http.read_timeout = @timeout

          req_class = request_class_for!(method)
          req = req_class.new(uri)

          default_headers.merge(headers || {}).each do |key, value|
            req[key] = value
          end

          req.body = JSON.generate(body) unless body.nil?

          response = http.request(req)
          status = response.code.to_i
          parsed = parse_response_json(response.body)

          if status == 401
            raise AuthenticationError.new(
              "Invalid or missing API key. Set RAYSURFER_API_KEY or pass api_key. Docs: https://docs.raysurfer.com/quickstart",
              status_code: status,
              details: parsed
            )
          end

          if RETRYABLE_STATUS_CODES.include?(status) && attempt < (MAX_RETRIES - 1)
            sleep(backoff_delay(attempt, retry_after_seconds(response)))
            attempt += 1
            next
          end

          if status == 429
            retry_after = retry_after_seconds(response)
            raise RateLimitError.new(
              "Rate limited by Raysurfer API.",
              retry_after: retry_after,
              status_code: status,
              details: parsed
            )
          end

          if status >= 400
            message = parsed.is_a?(Hash) && parsed["detail"] ? parsed["detail"].to_s : "API request failed"
            raise APIError.new(message, status_code: status, details: parsed)
          end

          return parsed
        rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT, EOFError, SocketError => e
          if attempt < (MAX_RETRIES - 1)
            sleep(backoff_delay(attempt, nil))
            attempt += 1
            next
          end

          raise CacheUnavailableError.new(
            "Failed to connect to Raysurfer after #{MAX_RETRIES} attempts: #{e.class}: #{e.message}",
            details: { method: method, path: path }
          )
        end
      end
    end

    def default_headers
      headers = {
        "Content-Type" => "application/json",
        "X-Raysurfer-SDK-Version" => "ruby/#{Raysurfer::VERSION}"
      }
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key && !@api_key.empty?
      headers["X-Raysurfer-Org-Id"] = @organization_id if @organization_id
      headers["X-Raysurfer-Workspace-Id"] = @workspace_id if @workspace_id
      headers["X-Raysurfer-Snips-Desired"] = @snips_desired if @snips_desired
      headers["X-Raysurfer-Public-Snips"] = "true" if @public_snips
      headers["X-Raysurfer-Agent-Id"] = @agent_id if @agent_id
      headers
    end

    def workspace_headers(workspace_id)
      return nil unless workspace_id

      { "X-Raysurfer-Workspace-Id" => workspace_id }
    end

    def request_class_for!(method)
      case method.to_s.upcase
      when "GET" then Net::HTTP::Get
      when "POST" then Net::HTTP::Post
      when "PATCH" then Net::HTTP::Patch
      when "PUT" then Net::HTTP::Put
      when "DELETE" then Net::HTTP::Delete
      else
        raise ArgumentError, "Unsupported HTTP method: #{method.inspect}. Expected one of GET, POST, PATCH, PUT, DELETE."
      end
    end

    def parse_response_json(body)
      return {} if body.nil? || body.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { "raw_body" => body }
    end

    def backoff_delay(attempt, retry_after)
      return retry_after if retry_after && retry_after.positive?

      RETRY_BASE_DELAY_SECONDS * (2**attempt)
    end

    def retry_after_seconds(response)
      raw = response["Retry-After"]
      return nil unless raw

      Float(raw)
    rescue ArgumentError
      nil
    end

    def normalize_file_written!(value)
      unless value.is_a?(Hash)
        raise ArgumentError,
              "Invalid file_written value: #{value.inspect}. Expected Hash with keys :path and :content. Docs: https://docs.raysurfer.com/sdk/curl#upload-code-from-an-execution-recommended"
      end

      path = value[:path] || value["path"]
      content = value[:content] || value["content"]

      ensure_non_empty_string!(path, "file_written.path")
      ensure_non_empty_string!(content, "file_written.content")

      { path: path, content: content }
    end

    def ensure_non_empty_string!(value, field_name)
      unless value.is_a?(String) && !value.strip.empty?
        raise ArgumentError,
              "Invalid #{field_name} value: #{value.inspect}. Expected non-empty String. Docs: https://docs.raysurfer.com/quickstart"
      end
    end

    def ensure_positive_number!(value, field_name)
      numeric = Float(value)
      return if numeric.positive?

      raise ArgumentError,
            "Invalid #{field_name} value: #{value.inspect}. Expected a positive number."
    rescue ArgumentError, TypeError
      raise ArgumentError,
            "Invalid #{field_name} value: #{value.inspect}. Expected a positive number."
    end

    def ensure_valid_url!(value)
      uri = URI.parse(value.to_s)
      return if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      raise ArgumentError,
            "Invalid base_url value: #{value.inspect}. Expected full HTTP(S) URL like https://api.raysurfer.com"
    rescue URI::InvalidURIError
      raise ArgumentError,
            "Invalid base_url value: #{value.inspect}. Expected full HTTP(S) URL like https://api.raysurfer.com"
    end

    def ensure_valid_snips_desired!(value)
      return if value.nil?
      return if %w[company client].include?(value)

      raise ArgumentError,
            "Invalid snips_desired value: #{value.inspect}. Expected \"company\" or \"client\". Docs: https://docs.raysurfer.com/sdk/curl"
    end
  end
end
