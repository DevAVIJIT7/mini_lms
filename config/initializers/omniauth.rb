OmniAuth.config.allowed_hosts = ["localhost"]
# OmniAuth.config.allowed_request_methods = [:get, :post]

Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :openid_connect,
    name: :mini_ams,
    issuer: "http://localhost:4000",
    discovery: false,
    scope: %i[openid profile email],
    response_type: :code,
    uid_field: "sub",
    client_options: {
      identifier: ENV.fetch("MINI_AMS_CLIENT_ID"),
      secret: ENV.fetch("MINI_AMS_CLIENT_SECRET"),
      redirect_uri: "http://localhost:3000/auth/mini_ams/callback",
      authorization_endpoint: "http://localhost:4000/oauth/authorize",
      token_endpoint: "http://localhost:4000/oauth/token",
      userinfo_endpoint: "http://localhost:4000/oauth/userinfo",
      jwks_uri: "http://localhost:4000/oauth/discovery/keys"
    }
  )
end