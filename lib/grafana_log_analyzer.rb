# frozen_string_literal: true

require_relative 'grafana_log_analyzer/client'
require_relative 'grafana_log_analyzer/loki'
require_relative 'grafana_log_analyzer/log_parser'
require_relative 'grafana_log_analyzer/analyzer'
require_relative 'grafana_log_analyzer/version'

module GrafanaLogAnalyzer
  class Error < StandardError; end
  class APIError < Error; end
  class ConfigError < Error; end
end
