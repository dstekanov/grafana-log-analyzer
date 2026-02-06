# frozen_string_literal: true

require 'json'
require 'logger'

module GrafanaLogAnalyzer
  # Loki log querying with retry logic.
  # Wraps the Grafana Loki query_range API endpoint.
  class Loki
    QUERY_RANGE_PATH = '/loki/api/v1/query_range'
    DEFAULT_LIMIT = 1000
    DEFAULT_TIME_RANGE = 3600 # 1 hour in seconds
    MAX_RETRIES = 3
    RETRY_DELAY = 3 # seconds

    attr_accessor :logger

    # @param client [GrafanaLogAnalyzer::Client] HTTP client
    def initialize(client)
      @client = client
      @logger = Logger.new($stdout)
      @logger.level = Logger::INFO
    end

    # Query Loki logs with automatic time range and retry logic.
    # @param query [String] LogQL query string
    # @param options [Hash] Optional parameters
    # @option options [Integer] :limit Max log lines (default: 1000)
    # @option options [Integer] :time_range Seconds to look back (default: 3600)
    # @option options [Integer] :max_retries Retry attempts (default: 3)
    # @option options [Integer] :retry_delay Delay between retries in seconds (default: 3)
    # @return [String] Raw log response body
    def query_range(query, options = {})
      limit = options[:limit] || DEFAULT_LIMIT
      time_range = options[:time_range] || DEFAULT_TIME_RANGE
      max_retries = options[:max_retries] || MAX_RETRIES
      retry_delay = options[:retry_delay] || RETRY_DELAY

      attempt = 1

      loop do
        current_end_time = Time.now
        current_start_time = current_end_time - time_range

        start_ns = current_start_time.to_i * 1_000_000_000
        end_ns = current_end_time.to_i * 1_000_000_000

        params = {
          query: query,
          limit: limit,
          start: start_ns,
          end: end_ns
        }

        @logger.info("Querying Grafana logs (attempt #{attempt}/#{max_retries})")
        @logger.info("Query: #{query}")
        @logger.info("Time range: #{current_start_time} - #{current_end_time}")
        @logger.info("Limit: #{limit}")

        response = @client.get(QUERY_RANGE_PATH, params)
        response = response.force_encoding('UTF-8') if response.is_a?(String)

        if logs_present?(response)
          @logger.info('Logs retrieved successfully')
          return response
        else
          @logger.warn('No logs found in response')

          if attempt >= max_retries
            @logger.error("Failed to retrieve logs after #{max_retries} attempts")
            return response
          end

          @logger.info("Retrying in #{retry_delay} seconds...")
          sleep(retry_delay)
          attempt += 1
        end
      end
    end

    # Build a LogQL query with environment label and filters.
    # @param filters [Array<String>] Filter strings to match
    # @param env [String] Environment name
    # @param env_suffix [String] Suffix appended to env in label (default: none).
    #   Example: env_suffix="-mse" produces {env="qa-mse"}
    # @return [String] Formatted LogQL query
    def build_query(*filters, env: nil, env_suffix: '')
      environment = env || ENV['ENVIRONMENT'] || 'production'
      env_label = "{env=\"#{environment}#{env_suffix}\"}"

      filter_clauses = filters.map { |filter| "|= `#{filter}`" }.join(' ')

      "#{env_label} #{filter_clauses}"
    end

    private

    def logs_present?(response)
      return false if response.nil? || response.empty?

      parsed = JSON.parse(response)
      result = parsed.dig('data', 'result')
      return false if result.nil? || result.empty?

      result.any? { |stream| stream['values']&.any? }
    rescue JSON::ParserError
      false
    end
  end
end
