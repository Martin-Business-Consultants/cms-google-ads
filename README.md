# Google Ads

A [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish) plugin: one Google Ads
account, read live through the Google Ads API, in the admin, the API and the `cms` CLI. Small on purpose:
the figures that tell you whether the money is working, the search terms that tell you what to exclude,
and the few changes worth making from here.

- **Google Ads page** (Content › Google Ads): spend, clicks, impressions, CTR, cost per click,
  conversions and cost per conversion for the last 7, 30 or 90 days beside the period before; spend by
  day; each campaign with its budget and figures; the search terms, each with an **Exclude** button that
  adds it to its campaign as a phrase-match negative.
- **API** (`/api/google_ads`): the overview, figures by day, campaigns, search terms, keywords and
  conversion actions for any range; any read-only GAQL query; and changes: negative keywords, pausing or
  enabling a campaign, and uploading an offline conversion by the click's gclid. Every change takes
  `validate_only` to dry-run, and is recorded in the audit log.

- **The guide** (Google Ads › Strategy, then each plan's Guide): steps a marketer from the big picture to a
  campaign ready to launch. **Strategy**, answered once and shared by every campaign: the business and its
  offer (and what it doesn't sell), customers and market, what a customer is worth (the guide works out
  what a lead and a click can cost and whether ads can pay), competitors, and exclusion lists. Then **each
  campaign**: goal and budget (checked against the economics), audience, ad groups, keywords, ad copy,
  landing pages, settings and exclusions, and pre-flight. Every step says why it matters, gives tips, and
  writes a **research prompt for Claude** from everything answered so far: copy it, run it in Claude,
  paste the reply back, and the guide reads its JSON into the step for you to review before saving
  (lists and ad groups show what they'd change first). Agents do the same through the API.
- **Exclusion lists** (Google Ads › Exclusion lists): negative keywords kept once by theme, synced to Google
  Ads as shared negative keyword lists and attached to each plan's campaign. The guide warns when one would
  block what you sell or a plan's own keywords.
- **Campaign plans** (Google Ads › Plans): plan a campaign before a cent is spent. A plan holds the goal,
  what success looks like and the date you'll decide, the budget and setup (each with a hint on why), its
  ad groups (keywords, landing page, a responsive search ad's headlines and descriptions with their
  character counts) and its negatives, and a checklist from research to that decision (Before you build,
  Build the campaign, Launch week, Every week, Every month, Decision), each task with a hint on how. Weekly
  and monthly tasks come due again. **Checks** flag what's wrong before it costs anything: copy over
  Google's limits, broad match on a small budget, landing pages that aren't published, negatives that would
  block the plan's own keywords, too many ad groups for the budget. Linked to the live campaign (its id),
  it's checked against it (Display Network on, budget different, negatives not yet added) and the missing
  negatives are added in one click. **Download for Ads Editor** gives a CSV that builds the campaign in
  Google Ads Editor (Account › Import), paused, to review there before posting.

Reads are cached for ten minutes and read fresh after a change made here.

## Setting it up

1. **Developer token.** In a Google Ads **manager account** (create one free if you don't have one, and
   link the ad account to it), go to **Tools › API Center** and apply. A new token has *Test* access, which
   only reads test accounts; apply for **Basic access** to use it on the real account (a short form; Google
   usually answers within a few days).
2. **OAuth client.** In the [Google Cloud console](https://console.cloud.google.com): create a project,
   enable the **Google Ads API**, set up the **OAuth consent screen** (External, with the Google account
   that signs in as a test user, or published), and **Credentials › Create credentials › OAuth client ID ›
   Web application** with the **authorised redirect URI** that Settings › Google Ads shows
   (`https://<your CMS>/cms/settings/google_ads/callback`).
3. In **Settings › Google Ads**, paste the client ID, client secret and developer token, save, and
   **Connect Google Ads** with a Google account that can see the ad account. The accounts it reaches are
   listed to choose from (the one that isn't a manager is picked for you). If the ad account sits under a
   manager account, put the manager's id in **Manager account ID**.

The client secret, developer token and tokens are kept among the Setting's encrypted secrets and never
read back.

## Capabilities

| Capability | Gives | Default roles |
|---|---|---|
| `google_ads:read` | The Google Ads page and every GET, and GAQL queries | Editor, Agent |
| `google_ads:plan` | Making and changing plans and their checklists | Editor, Agent |
| `google_ads:write` | Negative keywords, campaign status, conversion uploads | Admin only |

## The API

    GET   /api/google_ads                       ?days=30 (or ?from=2026-10-01&to=2026-10-31)
    GET   /api/google_ads/daily                 ?days
    GET   /api/google_ads/campaigns             ?days
    GET   /api/google_ads/search_terms          ?days&campaign_id&limit
    GET   /api/google_ads/keywords              ?days
    GET   /api/google_ads/conversion_actions
    POST  /api/google_ads/queries               {"query": "SELECT campaign.name, metrics.clicks FROM campaign WHERE segments.date DURING LAST_7_DAYS"}
    POST  /api/google_ads/negative_keywords     {"campaign_id": "…", "keywords": ["mowing", "snow"], "match_type": "PHRASE", "validate_only": true}
    PATCH /api/google_ads/campaigns/:id         {"status": "PAUSED", "validate_only": true}
    POST  /api/google_ads/conversions           {"gclid": "…", "conversion_action_id": "…", "at": "2026-10-20 14:30", "value": 2400}
    GET   /api/google_ads/plans                 (POST {plan: {..., negatives, ad_groups: [{name, landing_path, keywords: [...], headlines: [...], descriptions: [...]}]}, template: "search_leads"})
    GET   /api/google_ads/plans/:id             the plan, its checks, and the live campaign beside it (PATCH, DELETE)
    POST  /api/google_ads/plans/:id/ad_groups   (PATCH, DELETE …/ad_groups/:id)
    PATCH /api/google_ads/plans/:id/tasks/:id   {"done": true}
    GET   /api/google_ads/plans/:id/export      CSV for Google Ads Editor
    POST  /api/google_ads/plans/:id/negatives   {"validate_only": true}: add the plan's negatives the campaign lacks
    GET   /api/google_ads/guide                 the strategy's steps and where each stands (and /plans/:id/guide for a campaign's)
    GET   /api/google_ads/guide/:step           questions, answers, and the research prompt
    PATCH /api/google_ads/guide/:step           {"answers": {...}, "done": true}
    POST  /api/google_ads/guide/:step/answer    {"answer": "Claude's reply, or its JSON", "preview": true}
    GET   /api/google_ads/exclusion_lists       (POST, PATCH, DELETE; POST :id/sync {validate_only})
    POST  /api/google_ads/plans/:id/exclusions  sync the plan's lists and attach them to its campaign
    GET   /api/google_ads/settings              (PATCH with settings:write)

Ranges are whole days ending yesterday. Money is in the account's currency, as decimals; `ctr` is a
fraction. Google's refusals come back as `422 {"error": "google_ads", "message": "…"}` with Google's own
reason.

From the `cms` CLI, any of these works through the generic verbs:

    cms get '/api/google_ads/search_terms?days=7'
    cms post /api/google_ads/negative_keywords '{"campaign_id":"123","keywords":["mowing"],"validate_only":true}'

and, on a core with them, the `cms ads …` commands (`cms commands` lists them).

## Offline conversions

A lead form that keeps the ad click's `gclid` (the Healing Earth theme's `tracking` field does) lets you
tell Google which clicks became clients: create an **Import › Clicks** conversion action in Google Ads,
find its id with `GET /api/google_ads/conversion_actions`, and post each won lead's gclid to
`/api/google_ads/conversions` within 90 days of the click. Smart bidding then learns from clients, not
form fills.

## Development

Load it into a CMS checkout at `plugins/google_ads`, then:

    bin/rspec plugins/google_ads/spec
    bin/rubocop plugins/google_ads
    bundle exec herb lint plugins/google_ads/app

`GoogleAds::Client.transport` stands in for the network in specs (`spec/support/google_ads_helpers.rb`).

## License

[FSL-1.1-MIT](LICENSE.md).
