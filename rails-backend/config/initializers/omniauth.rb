# OmniAuth: Allow GET requests (API mode doesn't have CSRF tokens for POST)
OmniAuth.config.allowed_request_methods = [:get, :post]
OmniAuth.config.silence_get_warning = true
