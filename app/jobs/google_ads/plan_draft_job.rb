# frozen_string_literal: true

module GoogleAds
  # Drafts a new campaign plan with the install's AI (GoogleAds::PlanDraft).
  class PlanDraftJob < ApplicationJob
    queue_as :default

    def perform(user) = PlanDraft.for(user).run!
  end
end
