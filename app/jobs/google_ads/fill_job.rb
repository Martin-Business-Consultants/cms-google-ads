# frozen_string_literal: true

module GoogleAds
  # Fills a guide step with the install's AI (GoogleAds::Guide::Fill).
  class FillJob < ApplicationJob
    queue_as :default

    def perform(record, step_key, user = nil)
      step = Guide::Progress.new(record).steps.find { it.key == step_key.to_s } or return
      Guide::Fill.new(step, record).run!(user: user)
    end
  end
end
