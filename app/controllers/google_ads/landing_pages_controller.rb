# frozen_string_literal: true

module GoogleAds
  # An ad group's landing page built with the install's AI, as a draft
  # (GoogleAds::LandingPageBuild), from the guide's Landing pages step.
  class LandingPagesController < ApplicationController
    requires_capability "google_ads:plan", only: :create

    def create
      plan = GoogleAds::Plan.find(params[:plan_id])
      group = plan.ad_groups.find(params[:ad_group_id])
      back = google_ads_plan_guide_step_path(plan, "landing_pages")
      build = GoogleAds::LandingPageBuild.new(group)
      return redirect_to(back, alert: "Building pages takes Pages › write") unless Current.user.can?("pages:write")
      return redirect_to(back, alert: GoogleAds::Guide::Fill.unavailable_reason) unless GoogleAds::LandingPageBuild.available?
      return redirect_to(back, alert: "The page at #{group.landing_path} is published: change it in the page editor") unless build.buildable?

      build.start(user: Current.user) unless build.working?
      redirect_to back, notice: "The AI is building “#{group.name}”'s landing page from the site's blocks: a minute or two"
    end
  end
end
