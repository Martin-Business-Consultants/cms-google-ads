# frozen_string_literal: true

module GoogleAds
  # The guide, a step at a time: the strategy's steps (the brief) or a plan's.
  # A step's form saves its answers; a pasted research answer is read into
  # the form (or, for lists and ad groups, shown as changes) for review
  # before anything is saved.
  class GuideController < ApplicationController
    requires_capability "google_ads:read", only: :show
    requires_capability "google_ads:plan", only: [:update, :answer, :apply, :done]

    # What a step's screen and its partials read.
    View = Struct.new(:record, :plan, :brief, :step, :progress, :brief_progress, :prompt, :answer, :values, :pasted, :economics, :lists, :checks, keyword_init: true)

    before_action :set_record_and_step

    def show
      return redirect_to(step_path(@progress.next_step)) unless params[:step]

      prepare
    end

    def update
      values = params.fetch(:answers, {}).permit(*@step.fields.map(&:key)).to_h
      @record.assign_answers(values)
      @record.exclusion_list_ids = Array(params[:exclusion_list_ids]).compact_blank.map(&:to_i) if @step.kind == :setup
      if @record.save
        @record.mark_step!(@step.key) if params[:next] == "done"
        redirect_to (params[:next] ? step_path(following || @step) : step_path(@step)), notice: "Saved"
      else
        @values = values
        prepare
        render :show, status: :unprocessable_content
      end
    end

    # A pasted answer, read: a form step's form filled in (not saved), or the changes it would make.
    def answer
      @answer = GoogleAds::Guide::Answer.new(@step, @record, params.require(:answer))
      @values = @answer.values if @step.fields.any?
      @pasted = params[:answer]
      prepare
      flash.now[:notice] = @values ? "Filled in from the answer: check it, change what's wrong, then save." : "Here's what the answer would change."
      render :show
    rescue GoogleAds::Error => error
      @pasted = params[:answer]
      prepare
      flash.now[:alert] = error.message
      render :show, status: :unprocessable_content
    end

    def apply
      changes = GoogleAds::Guide::Answer.new(@step, @record, JSON.parse(params.require(:payload))).apply!
      redirect_to step_path(@step), notice: "Applied: #{changes.size} change#{"s" unless changes.size == 1}"
    rescue GoogleAds::Error, JSON::ParserError, ActiveRecord::RecordInvalid => error
      redirect_to step_path(@step), alert: error.message
    end

    def done
      @record.mark_step!(@step.key, done: params[:undo].blank?)
      redirect_to step_path(params[:undo].present? ? @step : (following || @step))
    end

    private

    def set_record_and_step
      @plan = GoogleAds::Plan.find(params[:plan_id]) if params[:plan_id]
      @record = @plan || GoogleAds::Brief.current
      @brief = @plan ? GoogleAds::Brief.current : @record
      @progress = GoogleAds::Guide::Progress.new(@record)
      return unless params[:step]

      @step = @progress.steps.find { it.key == params[:step] } or raise ActionController::RoutingError, "No step #{params[:step]}"
    end

    def prepare
      @brief_progress = @plan ? GoogleAds::Guide::Progress.new(@brief) : @progress
      @prompt = GoogleAds::Guide::Prompt.new(@step, @record, brief: @brief).to_s if @step.research?
      @economics = GoogleAds::Economics.new(@brief, daily_budget: @plan&.daily_budget) if %i[economics goal].include?(@step.kind)
      @lists = GoogleAds::ExclusionList.ordered.to_a if %i[exclusions setup].include?(@step.kind)
      @checks = GoogleAds::PlanChecks.new(@plan, live: GoogleAds::PlanLive.for(@plan)) if @plan && %i[landing_pages preflight].include?(@step.kind)
      @guide = View.new(record: @record, plan: @plan, brief: @brief, step: @step, progress: @progress, brief_progress: @brief_progress, prompt: @prompt,
        answer: @answer, values: @values, pasted: @pasted, economics: @economics, lists: @lists, checks: @checks)
    end

    def following
      steps = @progress.steps
      steps[steps.index(@step) + 1]
    end

    def step_path(step)
      @plan ? google_ads_plan_guide_step_path(@plan, step.key) : google_ads_strategy_step_path(step.key)
    end
    helper_method :step_path
  end
end
