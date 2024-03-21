# frozen_string_literal: true

module ShopifyApp
  module RetrieveSessionFromTokenExchange
    extend ActiveSupport::Concern
    include ShopifyApp::SanitizedParams

    class InvalidSessionTokenError < StandardError; end

    INVALID_JWT_ERRORS = [ShopifyAPI::Errors::InvalidJwtTokenError, ShopifyAPI::Errors::MissingJwtTokenError]

    included do
      rescue_from ShopifyAPI::Errors::HttpResponseError, with: :handle_http_error
    end

    def activate_shopify_session
      if current_shopify_session.blank?
        retrieve_session_from_token_exchange
      end

      if ShopifyApp.configuration.check_session_expiry_date && current_shopify_session.expired?
        retrieve_session_from_token_exchange
      end

      begin
        ShopifyApp::Logger.debug("Activating Shopify session")
        ShopifyAPI::Context.activate_session(current_shopify_session)
        yield
      ensure
        ShopifyApp::Logger.debug("Deactivating session")
        ShopifyAPI::Context.deactivate_session
      end
    end

    private

    def retrieve_session_from_token_exchange
        # TODO: Right now JWT Middleware only updates env['jwt.shopify_domain'] from request headers tokens, which won't work for new installs
        # We need to update the middleware to also update the env['jwt.shopify_domain'] from the query params
        domain = ShopifyApp::JWT.new(session_token).shopify_domain

        ShopifyApp::Logger.info("Peforming Token Exchange - Offline Access Token")
        session = exchange_token(
          shop: domain, # TODO: use jwt_shopify_domain ?
          session_token: session_token,
          requested_token_type: ShopifyAPI::Auth::TokenExchange::RequestedTokenType::OFFLINE_ACCESS_TOKEN,
        )

        if session && online_token_configured?
          ShopifyApp::Logger.info("Peforming Token Exchange - Online Access Token")
          session = exchange_token(
            shop: domain, # TODO: use jwt_shopify_domain ?
            session_token: session_token,
            requested_token_type: ShopifyAPI::Auth::TokenExchange::RequestedTokenType::ONLINE_ACCESS_TOKEN,
          )
        end

        #ShopifyApp.configuration.post_authenticate_tasks.perform(session) if session
    end

    def exchange_token(shop:, session_token:, requested_token_type:)
      if session_token.blank?
        respond_to_invalid_session_token
        return nil
      end

      begin
        session = ShopifyAPI::Auth::TokenExchange.exchange_token(
          shop: shop,
          session_token: session_token,
          requested_token_type: requested_token_type,
        )
      rescue ShopifyAPI::Errors::InvalidJwtTokenError
        respond_to_invalid_session_token
        return nil
      rescue ShopifyAPI::Errors::HttpResponseError => error
        ShopifyApp::Logger.info("A #{error.code} error (#{error.class.to_s}) occurred during the token exchange. Response: #{error.response.body}")
        raise
      rescue => error
        ShopifyApp::Logger.info("An error occurred during the token exchange: #{error.message}")
        raise
      end

      if session
        begin
          ShopifyApp::SessionRepository.store_session(session)
        rescue ActiveRecord::RecordNotUnique
          ShopifyApp::Logger.debug("Session not stored due to concurrent token exchange calls")
        end
      end

      return session
    end

    def session_token
      @session_token ||= id_token_header
    end

    def id_token_header
      request.headers["HTTP_AUTHORIZATION"]&.match(/^Bearer (.+)$/)&.[](1)
    end

    def online_token_configured?
      !ShopifyApp.configuration.user_session_repository.blank? && ShopifyApp::SessionRepository.user_storage.present?
    end

    def current_shopify_session
      @curent_shopify_session ||= begin
        session_id = begin
          ShopifyAPI::Utils::SessionUtils.current_session_id(request.headers["HTTP_AUTHORIZATION"], nil, online_token_configured?)
        rescue *INVALID_JWT_ERRORS
          nil
        end
        return nil unless session_id

        ShopifyApp::SessionRepository.load_session(session_id)
      end
    end

    def current_shopify_domain
      shopify_domain = sanitized_shop_name || current_shopify_session&.shop
      ShopifyApp::Logger.info("Installed store  - #{shopify_domain} deduced from user session")
      shopify_domain
    end

    def respond_to_invalid_session_token
      if request.xhr?
        response.set_header("X-Shopify-Retry-Invalid-Session-Request", 1)
        unauthorized_response = { message: :unauthorized }
        render(json: { errors: [unauthorized_response]  }, status: :unauthorized)
      else
        patch_session_token_url = "#{ShopifyAPI::Context.host}/patch_session_token"
        patch_session_token_params = request.query_parameters.except(:id_token)

        bounce_url = "#{ShopifyAPI::Context.host}#{request.path}?#{patch_session_token_params.to_query}"

        # App Bridge will trigger a fetch to the URL in shopify-reload, with a new session token in headers
        patch_session_token_params["shopify-reload"] = bounce_url

        redirect_to("#{patch_session_token_url}?#{patch_session_token_params.to_query}", allow_other_host: true)
      end
    end
  end
end
