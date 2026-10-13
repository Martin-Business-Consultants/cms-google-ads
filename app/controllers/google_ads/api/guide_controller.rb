# frozen_string_literal: true

module GoogleAds
  module Api
    # The guide for agents: /api/google_ads/guide (the strategy) and
    # /api/google_ads/plans/:plan_id/guide (a campaign). GET lists the steps
    # and where each stands; GET a step for its questions, answers and
    # research prompt; PATCH a step's answers; POST its research answer
    # (Claude's reply as text, or the JSON itself) to apply it, or with
    # preview: true to see what it would change.
    class GuideController < BaseController
      requires_capability "google_ads:read", only: [:index, :show]
      requires_capability "google_ads:plan", only: [:update, :answer]

      before_action :set_record
      before_action :set_step, except: :index

      def index
        render json: {scope: @record.guide_scope, plan_id: @plan&.id, next_step: @progress.next_step.key, steps: @progress.to_a,
                      economics: GoogleAds::Economics.new(GoogleAds::Brief.current, daily_budget: @plan&.daily_budget).to_h}
      end

      def show
        render json: step_json
      end

      def update
        @record.assign_answers(params.fetch(:answers, {}).permit(*@step.fields.map(&:key)).to_h)
        @record.exclusion_list_ids = Array(params[:exclusion_list_ids]).map(&:to_i) if @step.kind == :setup && params.key?(:exclusion_list_ids)
        @record.save!
        @record.mark_step!(@step.key, done: ActiveModel::Type::Boolean.new.cast(params[:done])) if params.key?(:done)
        render json: step_json
      end

      def answer
        raw = params.require(:answer)
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        answer = GoogleAds::Guide::Answer.new(@step, @record, raw)
        changes = ActiveModel::Type::Boolean.new.cast(params[:preview]) ? answer.changes : answer.apply!
        render json: {applied: !ActiveModel::Type::Boolean.new.cast(params[:preview]), changes: changes, notes: answer.notes, step: step_json}
      end

      private

      def set_record
        @plan = GoogleAds::Plan.find(params[:plan_id]) if params[:plan_id]
        @record = @plan || GoogleAds::Brief.current
        @progress = GoogleAds::Guide::Progress.new(@record)
      end

      def set_step
        @step = @progress.steps.find { it.key == params[:step] } or raise ActiveRecord::RecordNotFound, "No step #{params[:step]}"
      end

      def step_json
        @record.reload
        progress = GoogleAds::Guide::Progress.new(@record)
        {key: @step.key, title: @step.title, summary: @step.summary, why: @step.why, tips: @step.tips, status: progress.status(@step),
         fields: @step.fields.map { {key: it.key, label: it.label, type: it.type, required: it.required, hint: it.hint, value: @record.answer(it.key)} },
         exclusion_list_ids: (@step.kind == :setup) ? Array(@record.exclusion_list_ids) : nil,
         ad_groups: @plan && %i[structure keywords ads landing_pages preflight].include?(@step.kind) ? @plan.ad_groups.map(&:as_json) : nil,
         prompt: @step.research? ? GoogleAds::Guide::Prompt.new(@step, @record).to_s : nil, answer_format: @step.answer_format}.compact
      end
    end
  end
end
