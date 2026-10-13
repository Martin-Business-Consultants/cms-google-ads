# Google Ads, a Libre Publish plugin — guide for AI agents

A Rails engine loaded into a CMS install from `plugins/google_ads`. Read the core's `docs/plugins.md` and
`STYLE.md` first.

- `GoogleAds::Settings` lives in the core's Setting "google_ads"; the client secret, developer token,
  refresh and access tokens are among its secrets (never rendered or read back). `generation` is bumped
  by every change, and is part of every cache key.
- `GoogleAds::Client` does the OAuth web-server flow and the Google Ads REST API over Net::HTTP (only the
  core's gems, so no google-ads-googleads gem). Responses are camelCase JSON with int64s as strings.
  `GoogleAds::Client.transport` stands in for the network in specs.
- `GoogleAds::Report` is every read (GAQL, normalized: money as decimals, rates worked out).
  `GoogleAds::Changes` is every write; each takes `validate_only`, and records an Event.
  `GoogleAds::Accounts` lists the accounts a sign-in reaches.
- Plans: `GoogleAds::Plan` (+ `PlanAdGroup`, `PlanTask`, tables `google_ads_plans…`), `PlanTemplate`
  (phases, the checklist with hints, the field hints, defaults), `PlanChecks` (what's wrong, before and
  against the live campaign), `PlanLive` (the campaign and its negatives), `PlanExport` (Ads Editor CSV).
- The guide: `GoogleAds::Guide` (the steps: fields with hints, research task and answer JSON shape),
  `Guide::Progress`, `Guide::Prompt` (context from the brand brief, `Brief`, exclusion lists and the plan),
  `Guide::Answer` (reads pasted JSON, describes and applies it). `Brief` holds the strategy's answers;
  `Answerable` stores a step's fields in a column or `answers`. `Economics` turns the numbers into verdicts.
  `ExclusionList` + `SharedSets` (shared negative keyword sets in Google Ads).
- The API version is `GoogleAds::API_VERSION`, overridable in settings; Google retires versions about a
  year after release, so bump it when one sunsets.

Check: `bin/rspec plugins/google_ads/spec`, `bin/rubocop plugins/google_ads`, `bundle exec herb lint plugins/google_ads/app`.
