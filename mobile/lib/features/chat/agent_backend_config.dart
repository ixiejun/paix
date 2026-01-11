class AgentBackendConfig {
  const AgentBackendConfig({required this.baseUrl});

  final String baseUrl;

  static const String defaultBaseUrl = String.fromEnvironment(
    'AGENT_BACKEND_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const AgentBackendConfig localhost = AgentBackendConfig(baseUrl: defaultBaseUrl);
}
