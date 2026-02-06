# frozen_string_literal: true

require 'json'
require 'cgi'

module GrafanaLogAnalyzer
  # Utility class for parsing Grafana/Loki log responses.
  class LogParser
    # Parse JSON log entries from Loki response.
    # @param logs [String] Raw log response body
    # @return [Array<Hash>] Array of parsed log entries with :timestamp, :log, :parsed keys
    def self.parse_json_logs(logs)
      return [] if logs.nil? || logs.empty?

      response = JSON.parse(logs)
      result = response.dig('data', 'result') || []

      log_entries = []
      result.each do |stream|
        values = stream['values'] || []
        values.each do |timestamp, log_line|
          log_entries << {
            timestamp: timestamp,
            log: log_line,
            parsed: JSON.parse(log_line)
          }
        rescue JSON::ParserError
          log_entries << {
            timestamp: timestamp,
            log: log_line,
            parsed: nil
          }
        end
      end

      log_entries
    rescue JSON::ParserError => e
      raise Error, "Failed to parse Grafana logs response: #{e.message}"
    end

    # Check if logs contain a specific pattern.
    # @param logs [String] Raw log response body
    # @param pattern [String, Regexp] Pattern to search for
    # @return [Boolean]
    def self.contains?(logs, pattern)
      return false if logs.nil? || logs.empty?

      if pattern.is_a?(Regexp)
        !logs.match(pattern).nil?
      else
        logs.include?(pattern)
      end
    end

    # Format logs in a human-readable format.
    # @param logs [String] Raw log response body
    # @return [String] Formatted log output
    def self.format_logs(logs)
      return 'No logs to format' if logs.nil? || logs.empty?

      response = JSON.parse(logs)
      result = response.dig('data', 'result') || []

      return 'No log entries found' if result.empty?

      formatted_output = []
      result.each do |stream|
        values = stream['values'] || []
        values.each do |timestamp_ns, log_line|
          timestamp_sec = timestamp_ns.to_i / 1_000_000_000
          time = Time.at(timestamp_sec).strftime('%Y-%m-%d %H:%M:%S.%3N')
          formatted_output << "#{time} #{log_line}"
        end
      end

      formatted_output.join("\n")
    rescue JSON::ParserError => e
      "Failed to format logs: #{e.message}"
    end

    # Extract trace_ids from logs.
    # @param logs [String] Raw log response body
    # @return [Array<String>] Array of unique trace_ids
    def self.extract_trace_ids(logs)
      return [] if logs.nil? || logs.empty?

      trace_ids = []

      # Pattern 1: app.trace_id=<value>
      logs.scan(/app\.trace_id=([a-f0-9]+)/i).each { |match| trace_ids << match[0] }

      # Pattern 2: trace_id":"<value>" or trace_id=<value>
      logs.scan(/trace_id["']?\s*[":=]+\s*["']?([a-f0-9-]+)/i).each { |match| trace_ids << match[0] }

      # Pattern 3: uber-trace-id header format
      logs.scan(/uber-trace-id["']?\s*[":=]+\s*["']?([a-f0-9:]+)/i).each do |match|
        trace_ids << match[0].split(':').first
      end

      trace_ids.uniq
    end

    # Extract the first/primary trace_id from logs.
    # @param logs [String] Raw log response body
    # @return [String, nil] First trace_id found or nil
    def self.extract_trace_id(logs)
      extract_trace_ids(logs).first
    end

    # Extract args hash from network request logs.
    # @param logs [String] Raw log response body
    # @return [Hash, nil] Extracted args hash or nil
    def self.extract_args(logs)
      return nil if logs.nil? || logs.empty?

      decoded_logs = logs.gsub('\u003e', '>').gsub('\"', '"')

      match = decoded_logs.match(/args:\{([^}]+)\}/)
      return nil unless match

      parse_args_string(match[1])
    end

    # Build a Grafana Explore URL for viewing logs in the browser.
    # @param query [String] LogQL query string
    # @param base_url [String] Grafana base URL
    # @param from_time [Time, nil] Start time (default: 1 hour ago)
    # @param to_time [Time, nil] End time (default: now)
    # @return [String] Full Grafana Explore URL
    def self.build_explore_url(query, base_url:, from_time: nil, to_time: nil)
      to_time ||= Time.now
      from_time ||= to_time - 3600

      panes = {
        left: {
          datasource: 'grafanacloud-logs',
          queries: [{ refId: 'A', expr: query, queryType: 'range' }],
          range: { from: "now-#{((to_time - from_time) / 3600).ceil}h", to: 'now' }
        }
      }
      "#{base_url}/explore?panes=#{CGI.escape(JSON.generate(panes))}&schemaVersion=1"
    end

    class << self
      private

      def parse_args_string(args_string)
        args = {}

        args_string.scan(/:(\w+)=>([^,]+?)(?=,\s*:|$)/).each do |key, value|
          key_sym = key.to_sym
          cleaned_value = value.strip

          args[key_sym] = if cleaned_value == 'nil'
                            nil
                          elsif cleaned_value == 'true'
                            true
                          elsif cleaned_value == 'false'
                            false
                          elsif cleaned_value =~ /^"(.*)"$/
                            ::Regexp.last_match(1)
                          elsif cleaned_value =~ /^\d+$/
                            cleaned_value.to_i
                          else
                            cleaned_value
                          end
        end

        args
      end
    end
  end
end
