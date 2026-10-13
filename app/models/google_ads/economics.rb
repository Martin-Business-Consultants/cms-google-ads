# frozen_string_literal: true

# What the brief's numbers say a lead and a click are worth, and, with a
# plan's daily budget, what the budget buys: before a cent is spent, whether
# ads can pay here at all.
class GoogleAds::Economics
  DAYS_A_MONTH = 30.4

  def initialize(brief = GoogleAds::Brief.current, daily_budget: nil)
    @value = number(brief.answer(:client_value))
    @close = percent(brief.answer(:close_rate))
    @margin = percent(brief.answer(:margin))
    @cpc = number(brief.answer(:expected_cpc))
    @conversion = percent(brief.answer(:conversion_rate))
    @budget = daily_budget&.to_f
  end

  def complete? = [@value, @close, @margin, @cpc, @conversion].all?

  # Gross profit a lead brings, on average: the most a lead can cost to break even.
  def max_cost_per_lead = complete? ? (@value * @close * @margin).round(2) : nil
  def expected_cost_per_lead = complete? ? (@cpc / @conversion).round(2) : nil
  def break_even_cpc = complete? ? (max_cost_per_lead * @conversion).round(2) : nil

  def clicks_a_day = (@budget && @cpc) ? (@budget / @cpc).round(1) : nil
  def leads_a_month = (clicks_a_day && @conversion) ? (clicks_a_day * DAYS_A_MONTH * @conversion).round(1) : nil
  def customers_a_month = (leads_a_month && @close) ? (leads_a_month * @close).round(2) : nil
  def monthly_spend = @budget && (@budget * DAYS_A_MONTH).round

  def verdicts
    return [["warning", "Fill in What a customer is worth to see whether ads can pay."]] unless complete?

    out = []
    if expected_cost_per_lead > max_cost_per_lead
      out << ["problem", "At $#{fmt(@cpc)} a click and #{pct(@conversion)} of clicks becoming leads, a lead costs about $#{fmt(expected_cost_per_lead)}, " \
                         "more than the $#{fmt(max_cost_per_lead)} it's worth. It only pays if the page converts better, clicks are cheaper, or customers are worth more."]
    else
      out << ["ok", "A lead should cost about $#{fmt(expected_cost_per_lead)} against $#{fmt(max_cost_per_lead)} it's worth: room to pay up to $#{fmt(break_even_cpc)} a click."]
    end
    if clicks_a_day
      out << ((clicks_a_day < 10) ? ["warning", "$#{fmt(@budget)} a day buys about #{clicks_a_day} clicks: under 10 a day, it takes months to learn which keywords work."] :
                                    ["ok", "$#{fmt(@budget)} a day buys about #{clicks_a_day} clicks, #{leads_a_month} leads and #{customers_a_month} customers a month."])
    end
    out
  end

  def to_h
    {complete: complete?, max_cost_per_lead: max_cost_per_lead, expected_cost_per_lead: expected_cost_per_lead, break_even_cpc: break_even_cpc,
     clicks_a_day: clicks_a_day, leads_a_month: leads_a_month, customers_a_month: customers_a_month, monthly_spend: monthly_spend,
     verdicts: verdicts.map { {level: it[0], message: it[1]} }}
  end

  private

  def number(value) = value.presence && value.to_f.positive? ? value.to_f : nil
  def percent(value) = number(value) && (number(value) / 100.0)
  def fmt(value) = format((value % 1).zero? ? "%.0f" : "%.2f", value)
  def pct(value) = "#{fmt(value * 100)}%"
end
