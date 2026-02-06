# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module GrafanaLogAnalyzer
  # HTTP client for Grafana Loki API.
  # Supports basic auth and configurable base URL.
  class Client
    attr_reader :base_url

    # @param url [String] Grafana Loki base URL (e.g. "https://logs-prod3.grafana.net")
    # @param user [String] Basic auth username
    # @param password [String] Basic auth password/token
    def initialize(url:, user:, password:)
      @base_url = url
      @user = user
      @password = password
    end

    # Build a Client from environment variables.
    # @param url_env [String] env var name for URL (default: GRAFANA_URL)
    # @param user_env [String] env var name for user (default: GRAFANA_USER)
    # @param password_env [String] env var name for password (default: GRAFANA_PASSWORD)
    # @return [Client]
    def self.from_env(url_env: 'GRAFANA_URL', user_env: 'GRAFANA_USER', password_env: 'GRAFANA_PASSWORD')
      url = ENV[url_env] || raise(ConfigError, "#{url_env} environment variable is not set")
      user = ENV[user_env] || raise(ConfigError, "#{user_env} environment variable is not set")
      password = ENV[password_env] || raise(ConfigError, "#{password_env} environment variable is not set")

      new(url: url, user: user, password: password)
    end

    # Send a GET request.
    # @param path [String] API path (e.g. "/loki/api/v1/query_range")
    # @param params [Hash] Query parameters
    # @return [String] Response body
    def get(path, params = {})
      url = build_url(path, params)

      request = Net::HTTP::Get.new(url)
      request.basic_auth(@user, @password)
      request['Accept'] = 'application/json'

      response = Net::HTTP.start(url.hostname, url.port, use_ssl: url.scheme == 'https') do |http|
        http.request(request)
      end

      handle_response(response)
    end

    private

    def build_url(path, params)
      full_url = @base_url + path
      unless params.empty?
        query_string = URI.encode_www_form(params)
        full_url += "?#{query_string}"
      end
      URI.parse(full_url)
    end

    def handle_response(response)
      unless response.code == '200'
        error_message = "Grafana API returned HTTP #{response.code}"
        begin
          error_body = JSON.parse(response.body)
          error_message += ": #{error_body['message'] || error_body['error']}" if error_body
        rescue JSON::ParserError
          error_message += ": #{response.body}"
        end
        raise APIError, error_message
      end

      response.body
    end
  end
end
