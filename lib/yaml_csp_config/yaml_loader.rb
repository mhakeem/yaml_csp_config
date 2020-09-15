# frozen_string_literal: true

module YamlCspConfig
  # The entity that is responsible for loading the YAML and applying overrides
  class YamlLoader
    DIRECTIVES = %i[
      base_uri
      child_src
      connect_src
      default_src
      font_src
      form_action
      frame_ancestors
      frame_src
      img_src
      manifest_src
      media_src
      object_src
      prefetch_src
      script_src
      style_src
      worker_src
    ].freeze

    class << self
      def call(policy, config_file = YamlCspConfig.configuration.configuration_file_path)
        new(policy, config_file).configure
      end
    end

    def initialize(
      policy,
      config_file_path,
      group_key: YamlCspConfig.configuration.default_env_var_group_key,
      var_key_prefix: YamlCspConfig.configuration.default_env_var_additions_key_prefix
    )
      raise ArgumentError, "Config file doesn't exist" unless File.exist?(config_file_path)

      @policy = policy
      @config_file_path = config_file_path
      @env_var_group_key = group_key
      @env_var_key_prefix = var_key_prefix
    end

    def configure
      configure_with_overrides.each do |rule, values|
        unless policy.respond_to?(rule.to_sym)
          raise StandardError, "A CSP configuration was defined for an unsupported directive/setting: #{rule}"
        end

        policy.send(rule, *values)
      end

      policy
    end

    private

    attr_reader :policy, :config_file_path, :env_var_group_key, :env_var_key_prefix

    def yaml
      @yaml ||= begin
        parsed = ERB.new(File.read(config_file_path)).result(binding)
        YAML.safe_load(parsed, permitted_classes: [Symbol])
      end
    end

    def csp_config
      @csp_config ||= HashWithIndifferentAccess.new(yaml[YamlCspConfig.configuration.yaml_config_base_key.to_s])
    end

    def configure_with_overrides
      env_override
      env_var_group_override
      env_var_direct_override
      csp_config
    end

    # Override with any Rails env specific config
    def env_override
      yaml[Rails.env]&.each { |k, v| add_to(k, v) }
    end

    # Optional an overriding config group can be specified by name in an environment variable
    def env_var_group_override
      group_name = ENV[env_var_group_key]
      return if group_name.nil? || group_name.empty? || group_name == Rails.env

      yaml[group_name]&.each { |k, v| add_to(k, v) }
    end

    # Allow environment variables to add to rules
    def env_var_direct_override
      DIRECTIVES.each do |rule|
        k = env_var_key_prefix + rule.to_s.upcase
        add_to(rule, ENV[k].split(" ")) if ENV[k].present?
      end
    end

    def add_to(rule, value)
      csp_config[rule] ||= []
      csp_config[rule] += value
    end
  end
end
