# frozen_string_literal: true

module GoogleAds
  # The plugin's admin screens: a 404 while it's off.
  class ApplicationController < ::ApplicationController
    include PluginGated
    plugin :google_ads

    private

    def set_plan
      @plan = GoogleAds::Plan.find(params[:plan_id] || params[:id])
    end
  end
end
