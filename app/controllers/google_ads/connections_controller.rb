# frozen_string_literal: true

module GoogleAds
  # Connecting Google Ads: off to Google's sign-in (new), and forgetting the sign-in (destroy).
  class ConnectionsController < ::Settings::BaseController
    include PluginGated
    plugin :google_ads

    requires_capability "settings:write", only: [:new, :destroy]

    # A link (GET), since the admin's Content-Security-Policy (form-action 'self')
    # stops a form's redirect to accounts.google.com.
    def new
      settings = GoogleAds::Settings.current
      return redirect_to(settings_google_ads_path, alert: "Add the OAuth client's ID and secret first") unless settings.client?

      session[:google_ads_oauth_state] = SecureRandom.urlsafe_base64(24)
      redirect_to GoogleAds::Client.new(settings: settings).authorize_url(redirect_uri: settings_google_ads_callback_url, state: session[:google_ads_oauth_state]),
        allow_other_host: true
    end

    def destroy
      GoogleAds::Settings.disconnect
      Event.record("settings.google_ads_disconnected")
      redirect_to settings_google_ads_path, notice: "Google Ads disconnected"
    end
  end
end
