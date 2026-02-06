# frozen_string_literal: true

require 'json'
require 'yaml'
require 'cgi'

module GrafanaLogAnalyzer
  # Main log analyzer. Queries Grafana/Loki logs by identifier and mode,
  # then produces structured results (root cause, timeline, recommendations).
  #
  # All configuration (search patterns, env suffix, Grafana URLs) is injectable
  # so this works for any project, not just a specific one.
  class Analyzer
    DEFAULT_HOURS = 3
    VALID_MODES = %w[full errors workflows network trace timeline].freeze
    VALID_FORMATS = %w[compact json].freeze

    DEFAULT_SEARCH_PATTERNS = {
      errors: %w[ERROR Exception failed timeout rejected],
      workflows: ['Workflow::', 'Temporal'],
      network: ['API client', 'proxy'],
      billing: %w[charge invoice payment balance],
      validation: %w[validation invalid required missing]
    }.freeze

    TRACE_ID_PATTERNS = [
      /app\.trace_id=([a-f0-9]{32})/i,
      /trace_id=([a-f0-9]{32})/i,
      /trace_id\\?"\\?:\s*\\?"([a-f0-9]{32})\\?"/i
    ].freeze

    attr_reader :results

    # @param identifiers [Hash] Test data identifiers
    #   Supported keys: :subscription_uuid, :account_uuid, :msisdn, :iccid, :imei
    # @param hours [Integer] Time range in hours to search
    # @param mode [String] Analysis mode (full, errors, workflows, network, trace, timeline)
    # @param config [Hash] Configuration options
    # @option config [String] :grafana_url Grafana base URL
    # @option config [String] :grafana_user Basic auth user
    # @option config [String] :grafana_password Basic auth password
    # @option config [String] :env Environment name (e.g. "qa", "dev200")
    # @option config [String] :env_suffix Suffix for env label (e.g. "-mse" → {env="qa-mse"})
    # @option config [Hash] :search_patterns Custom search patterns per category
    # @option config [Array<String>] :network_patterns Custom network provider patterns
    def initialize(identifiers, hours: DEFAULT_HOURS, mode: 'full', config: {})
      @identifiers = identifiers
      @hours = hours
      @mode = mode
      @time_range_seconds = hours * 3600
      @trace_ids = []
      @config = config

      @env = config[:env] || ENV['ENVIRONMENT'] || 'production'
      @env_suffix = config[:env_suffix] || ''
      @search_patterns = config[:search_patterns] || DEFAULT_SEARCH_PATTERNS
      @network_patterns = config[:network_patterns] || @search_patterns[:network]

      @client = build_client(config)
      @loki = Loki.new(@client)

      @results = {
        identifiers: identifiers,
        hours_analyzed: hours,
        mode: mode,
        time_range_analyzed: nil,
        queries_executed: [],
        log_entries: [],
        trace_ids_found: [],
        workflow_timeline: [],
        root_cause: nil,
        recommendations: [],
        grafana_urls: {}
      }
    end

    def analyze
      start_time = Time.now

      primary_id = find_primary_identifier
      return no_identifier_error if primary_id.nil?

      puts "Starting log analysis with primary identifier: #{primary_id}"
      puts "Time range: #{@hours} hours | Mode: #{@mode}"

      search_for_errors(primary_id) if run_phase?(:errors)
      search_for_workflows(primary_id) if run_phase?(:workflows)

      search_for_network_calls if run_phase?(:network) && (@identifiers[:subscription_uuid] || @identifiers[:iccid])

      search_by_trace_ids if run_phase?(:trace) && @results[:log_entries].empty? && @trace_ids.any?

      build_workflow_timeline(primary_id) if run_phase?(:timeline)

      determine_root_cause
      generate_recommendations
      generate_grafana_urls(primary_id)

      end_time = Time.now
      @results[:time_range_analyzed] =
        "#{start_time.strftime('%Y-%m-%d %H:%M:%S')} - #{end_time.strftime('%Y-%m-%d %H:%M:%S')} UTC"
      @results[:trace_ids_found] = @trace_ids.uniq

      @results
    end

    def to_json(*_args)
      JSON.pretty_generate(@results)
    end

    def to_compact
      out = []
      out << "# Log Analysis: #{@mode} mode (#{@hours}h)"
      out << ''

      if @results[:root_cause]
        rc = @results[:root_cause]
        out << '## Root Cause'
        out << "**#{rc[:category]}**: #{rc[:summary]}"
        out << "`#{rc[:details][0..200]}`" if rc[:details]
        out << ''
      end

      if @results[:log_entries].any?
        out << "## Log Entries (#{@results[:log_entries].length})"
        @results[:log_entries].first(15).each do |entry|
          out << "[#{entry[:timestamp]}] **#{entry[:level]}** #{entry[:message][0..200]}"
        end
        out << "_...and #{@results[:log_entries].length - 15} more_" if @results[:log_entries].length > 15
        out << ''
      end

      if @results[:workflow_timeline].any?
        out << "## Timeline (#{@results[:workflow_timeline].length} events)"
        @results[:workflow_timeline].first(20).each do |evt|
          icon = case evt[:event_type].to_s
                 when 'error' then 'ERR'
                 when /workflow/ then 'WF'
                 when /activity/ then 'ACT'
                 when 'grpc_call' then 'GRPC'
                 when 'kafka_event' then 'KAFKA'
                 when 'network_call' then 'NET'
                 else 'INFO'
                 end
          out << "[#{evt[:timestamp]}] [#{icon}] #{evt[:service]}: #{evt[:description][0..150]}"
        end
        out << "_...and #{@results[:workflow_timeline].length - 20} more_" if @results[:workflow_timeline].length > 20
        out << ''
      end

      if @results[:trace_ids_found].any?
        out << '## Trace IDs'
        @results[:trace_ids_found].first(5).each { |tid| out << "- `#{tid}`" }
        out << ''
      end

      if @results[:grafana_urls].any?
        out << '## Grafana Links'
        @results[:grafana_urls].each { |key, url| out << "- **#{key}**: #{url}" }
        out << ''
      end

      if @results[:recommendations].any?
        out << '## Recommendations'
        @results[:recommendations].each { |r| out << "- #{r}" }
      end

      out.join("\n")
    end

    private

    def run_phase?(phase)
      @mode == 'full' || @mode == phase.to_s
    end

    def find_primary_identifier
      @identifiers[:subscription_uuid] ||
        @identifiers[:account_uuid] ||
        @identifiers[:msisdn] ||
        @identifiers[:iccid] ||
        @identifiers[:imei]
    end

    def no_identifier_error
      @results[:root_cause] = {
        category: 'unknown',
        summary: 'No identifiers provided',
        details: 'Cannot analyze logs without at least one identifier (subscription_uuid, account_uuid, msisdn, iccid, or imei)'
      }
      @results
    end

    def build_client(config)
      if config[:grafana_url] && config[:grafana_user] && config[:grafana_password]
        Client.new(
          url: config[:grafana_url],
          user: config[:grafana_user],
          password: config[:grafana_password]
        )
      else
        Client.from_env
      end
    end

    def search_for_errors(identifier)
      puts '  Searching for errors...'

      @search_patterns[:errors].each do |error_pattern|
        query = @loki.build_query(identifier, error_pattern, env: @env, env_suffix: @env_suffix)
        @results[:queries_executed] << query

        logs = @loki.query_range(query, time_range: @time_range_seconds, max_retries: 1)
        next unless logs_present?(logs)

        extract_trace_ids(logs)
        entries = LogParser.parse_json_logs(logs)
        entries.each do |entry|
          @results[:log_entries] << {
            timestamp: format_timestamp(entry[:timestamp]),
            level: 'ERROR',
            message: truncate_message(entry[:log]),
            pattern_matched: error_pattern
          }
        end
      end
    end

    def search_for_workflows(identifier)
      puts '  Searching for workflow execution...'

      @search_patterns[:workflows].each do |workflow_pattern|
        query = @loki.build_query(identifier, workflow_pattern, env: @env, env_suffix: @env_suffix)
        @results[:queries_executed] << query

        logs = @loki.query_range(query, time_range: @time_range_seconds, max_retries: 1)
        next unless logs_present?(logs)

        extract_trace_ids(logs)

        next unless LogParser.contains?(logs, 'failed') || LogParser.contains?(logs, 'error')

        entries = LogParser.parse_json_logs(logs)
        entries.each do |entry|
          next unless entry[:log].match?(/failed|error|timeout/i)

          @results[:log_entries] << {
            timestamp: format_timestamp(entry[:timestamp]),
            level: 'WORKFLOW',
            message: truncate_message(entry[:log]),
            pattern_matched: workflow_pattern
          }
        end
      end
    end

    def search_for_network_calls
      puts '  Searching for network provider calls...'

      identifier = @identifiers[:subscription_uuid] || @identifiers[:iccid]

      @network_patterns.each do |network_pattern|
        query = @loki.build_query(identifier, network_pattern, env: @env, env_suffix: @env_suffix)
        @results[:queries_executed] << query

        logs = @loki.query_range(query, time_range: @time_range_seconds, max_retries: 1)
        next unless logs_present?(logs)

        extract_trace_ids(logs)

        args = LogParser.extract_args(logs)
        if args
          @results[:network_call_args] ||= []
          @results[:network_call_args] << { pattern: network_pattern, args: args }
        end

        next unless LogParser.contains?(logs, 'ERROR') || LogParser.contains?(logs, 'failed')

        entries = LogParser.parse_json_logs(logs)
        entries.each do |entry|
          next unless entry[:log].match?(/error|failed|rejected/i)

          @results[:log_entries] << {
            timestamp: format_timestamp(entry[:timestamp]),
            level: 'NETWORK_ERROR',
            message: truncate_message(entry[:log]),
            pattern_matched: network_pattern
          }
        end
      end
    end

    def search_by_trace_ids
      puts '  No errors found with primary ID, searching by trace_id...'

      @trace_ids.uniq.first(3).each do |trace_id|
        query = @loki.build_query(trace_id, 'ERROR', env: @env, env_suffix: @env_suffix)
        @results[:queries_executed] << query

        logs = @loki.query_range(query, time_range: @time_range_seconds, max_retries: 1)
        next unless logs_present?(logs)

        entries = LogParser.parse_json_logs(logs)
        entries.each do |entry|
          @results[:log_entries] << {
            timestamp: format_timestamp(entry[:timestamp]),
            level: 'ERROR',
            message: truncate_message(entry[:log]),
            pattern_matched: "trace_id:#{trace_id}"
          }
        end
      end
    end

    def extract_trace_ids(logs)
      return if logs.nil? || logs.empty?

      TRACE_ID_PATTERNS.each do |pattern|
        logs.scan(pattern).flatten.each do |trace_id|
          @trace_ids << trace_id unless @trace_ids.include?(trace_id)
        end
      end
    end

    def build_workflow_timeline(identifier)
      puts '  Building workflow timeline...'

      query = @loki.build_query(identifier, env: @env, env_suffix: @env_suffix)
      @results[:queries_executed] << query

      logs = @loki.query_range(query, time_range: @time_range_seconds, limit: 500, max_retries: 1)
      return unless logs_present?(logs)

      timeline_entries = []
      parsed = JSON.parse(logs)
      parsed.dig('data', 'result')&.each do |stream|
        stream['values']&.each do |ts_ns, log_line|
          entry = parse_timeline_entry(ts_ns, log_line)
          timeline_entries << entry if entry
        end
      end

      @results[:workflow_timeline] = timeline_entries
                                     .sort_by { |e| e[:timestamp_ns] }
                                     .map { |e| e.except(:timestamp_ns) }

      puts "  Found #{timeline_entries.length} workflow events"
    rescue JSON::ParserError => e
      puts "  Failed to parse timeline logs: #{e.message}"
    end

    def parse_timeline_entry(ts_ns, log_line)
      timestamp = Time.at(ts_ns.to_i / 1_000_000_000)
      timestamp_str = timestamp.strftime('%Y-%m-%d %H:%M:%S.%3N')

      parsed = begin
        JSON.parse(log_line)
      rescue StandardError
        nil
      end

      if parsed
        service = parsed['service'] || parsed['NOMAD_TASK_NAME'] || extract_service_from_log(log_line)
        level = parsed['level'] || 'INFO'
        msg = parsed['msg'] || parsed['message'] || ''
        workflow = parsed['WorkflowType'] || parsed['workflow_type']
        activity = parsed['ActivityType'] || parsed['activity_type']
        error = parsed['error'] || parsed['err']

        event_type = determine_event_type(level, msg, _workflow = workflow, activity, error)
        return nil if event_type == :skip

        {
          timestamp_ns: ts_ns.to_i,
          timestamp: timestamp_str,
          service: normalize_service_name(service || 'unknown'),
          event_type: event_type,
          description: build_event_description(msg, workflow, activity, error),
          level: level
        }
      else
        event_type = determine_event_type_from_raw(log_line)
        return nil if event_type == :skip

        {
          timestamp_ns: ts_ns.to_i,
          timestamp: timestamp_str,
          service: extract_service_from_log(log_line),
          event_type: event_type,
          description: extract_description_from_log(log_line),
          level: extract_level_from_log(log_line)
        }
      end
    end

    def determine_event_type(level, msg, _workflow, activity, error)
      return :error if level == 'ERROR' || error.to_s.length > 0
      return :workflow_start if msg =~ /Starting.*Workflow|Triggering.*workflow/i
      return :workflow_complete if msg =~ /Workflow.*completed|completed.*successfully/i
      return :activity_start if activity || msg =~ /Starting.*Activity|Execute.*Activity/i
      return :activity_complete if msg =~ /Activity.*completed/i
      return :kafka_event if msg =~ /kafka|Produced.*message|consuming.*topic/i
      return :grpc_call if msg =~ /GRPC|gRPC/i
      return :network_call if msg =~ /API Request|API Response|client.*request/i
      return :subscription_update if msg =~ /updated|created|record/i
      return :skip if msg.to_s.empty? || msg =~ /^\s*$/

      :info
    end

    def determine_event_type_from_raw(log_line)
      return :error if log_line =~ /ERROR|Exception|failed/i
      return :workflow_start if log_line =~ /Starting.*Workflow|Triggering.*workflow/i
      return :activity_start if log_line =~ /Starting.*Activity/i
      return :grpc_call if log_line =~ /GRPC request|gRPC/i
      return :network_call if log_line =~ /client.*request|API.*Request/i
      return :subscription_update if log_line =~ /updated|record/i

      :info
    end

    def build_event_description(msg, workflow, activity, error)
      parts = []
      parts << "[WF: #{workflow}]" if workflow
      parts << "[ACT: #{activity}]" if activity
      parts << msg[0..150] if msg.to_s.length > 0
      parts << "[ERROR: #{error[0..100]}]" if error.to_s.length > 0
      parts.join(' ').strip
    end

    def extract_service_from_log(log_line)
      if log_line =~ /app\.service=([\w-]+)/
        normalize_service_name(::Regexp.last_match(1))
      elsif log_line =~ /service[":]\s*["']?([\w-]+)/
        normalize_service_name(::Regexp.last_match(1))
      else
        'unknown'
      end
    end

    def extract_description_from_log(log_line)
      if log_line =~ /\[INFO\]\s*\[(.{1,150})/
        ::Regexp.last_match(1).gsub(/\].*/, '')
      elsif log_line =~ /"message"\s*:\s*"([^"]{1,150})/
        ::Regexp.last_match(1)
      else
        log_line[0..150]
      end
    end

    def extract_level_from_log(log_line)
      return 'ERROR' if log_line =~ /\[ERROR\]|"level"\s*:\s*"ERROR"/i
      return 'WARN' if log_line =~ /\[WARN\]|"level"\s*:\s*"WARN"/i
      return 'DEBUG' if log_line =~ /\[DEBUG\]|"level"\s*:\s*"DEBUG"/i

      'INFO'
    end

    def normalize_service_name(service)
      service.to_s
    end

    def determine_root_cause
      if @results[:log_entries].any?
        error_entries = @results[:log_entries].select { |e| %w[ERROR NETWORK_ERROR].include?(e[:level]) }
        first_error = error_entries.first || @results[:log_entries].first

        @results[:root_cause] = {
          category: 'errors_found',
          summary: "Found #{@results[:log_entries].length} log entries with errors/issues",
          details: first_error[:message],
          first_error_timestamp: first_error[:timestamp]
        }
      else
        @results[:root_cause] = {
          category: 'no_errors_found',
          summary: 'No errors found in logs',
          details: 'The logs do not contain obvious error patterns. The issue may be timing-related or in a different service.'
        }
      end
    end

    def generate_recommendations
      @results[:recommendations] = if @results[:log_entries].any?
                                     [
                                       'Review the error messages above for specific failure details',
                                       'Check workflow status in your workflow engine UI',
                                       'Use the Grafana URLs below to explore logs in detail',
                                       'Search by trace_id for distributed tracing across services'
                                     ]
                                   else
                                     [
                                       'Extend time range with --hours option',
                                       'Check related services',
                                       'Review test timing and wait conditions',
                                       'Check environment health status'
                                     ]
                                   end
    end

    def generate_grafana_urls(primary_id)
      base_url = @config[:grafana_url] || ENV['GRAFANA_URL'] || 'https://grafana.example.com'

      all_query = @loki.build_query(primary_id, env: @env, env_suffix: @env_suffix)
      error_query = @loki.build_query(primary_id, env: @env, env_suffix: @env_suffix)
      error_query = "#{error_query} |~ `ERROR|failed|exception`"

      @results[:grafana_urls] = {
        all_logs: LogParser.build_explore_url(all_query, base_url: base_url),
        errors_only: LogParser.build_explore_url(error_query, base_url: base_url)
      }

      return unless @trace_ids.any?

      trace_query = @loki.build_query(@trace_ids.first, 'ERROR', env: @env, env_suffix: @env_suffix)
      @results[:grafana_urls][:by_trace_id] = LogParser.build_explore_url(trace_query, base_url: base_url)
    end

    def logs_present?(logs)
      return false if logs.nil? || logs.empty?

      parsed = JSON.parse(logs)
      result = parsed.dig('data', 'result')
      result&.any? { |stream| stream['values']&.any? }
    rescue JSON::ParserError
      false
    end

    def format_timestamp(timestamp_ns)
      timestamp_sec = timestamp_ns.to_i / 1_000_000_000
      Time.at(timestamp_sec).strftime('%Y-%m-%d %H:%M:%S')
    end

    def truncate_message(message, max_length = 500)
      return message if message.length <= max_length

      "#{message[0...max_length]}..."
    end
  end
end
