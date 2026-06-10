enum Fixtures {
    /// Verbatim response from api.anthropic.com/api/oauth/usage on 2026-06-10.
    /// Note: resets_at carries MICROSECOND fractional seconds — the decoder
    /// must not assume 3-digit milliseconds.
    static let liveUsageResponse = #"""
    {
        "five_hour": {
            "utilization": 77.0,
            "resets_at": "2026-06-11T00:49:59.764212+00:00"
        },
        "seven_day": {
            "utilization": 30.0,
            "resets_at": "2026-06-14T04:59:59.764237+00:00"
        },
        "seven_day_oauth_apps": null,
        "seven_day_opus": null,
        "seven_day_sonnet": {
            "utilization": 2.0,
            "resets_at": "2026-06-14T04:59:59.764247+00:00"
        },
        "seven_day_cowork": null,
        "seven_day_omelette": null,
        "tangelo": null,
        "iguana_necktie": null,
        "omelette_promotional": null,
        "cinder_cove": null,
        "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 500,
            "used_credits": 0.0,
            "utilization": null,
            "currency": "USD",
            "disabled_reason": null
        }
    }
    """#
}
