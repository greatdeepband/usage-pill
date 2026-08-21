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
        },
        "spend": {
            "used": {
                "amount_minor": 14437,
                "currency": "EUR",
                "exponent": 2
            },
            "limit": null,
            "percent": 0,
            "severity": "normal",
            "enabled": true,
            "disabled_reason": null
        }
    }
    """#

    /// Verbatim response from api.anthropic.com/api/oauth/usage on 2026-08-21.
    /// This is the shape that carries the `limits` array — the Fable weekly
    /// window lives ONLY there (kind "weekly_scoped", scope.model.display_name
    /// "Fable", utilization under `percent` as an integer), never as a
    /// top-level bucket.
    static let liveUsageResponseWithLimits = #"""
    {
        "five_hour": {
            "utilization": 9.0,
            "resets_at": "2026-08-21T21:49:59.960275+00:00",
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
        },
        "seven_day": {
            "utilization": 75.0,
            "resets_at": "2026-08-23T04:59:59.960293+00:00",
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
        },
        "seven_day_oauth_apps": null,
        "seven_day_opus": null,
        "seven_day_sonnet": null,
        "seven_day_cowork": null,
        "seven_day_omelette": null,
        "tangelo": null,
        "iguana_necktie": null,
        "omelette_promotional": null,
        "nimbus_quill": {
            "utilization": 0.0,
            "resets_at": null,
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
        },
        "cinder_cove": null,
        "amber_ladder": null,
        "extra_usage": {
            "is_enabled": false,
            "monthly_limit": null,
            "used_credits": 1221.0,
            "utilization": null,
            "currency": "EUR",
            "decimal_places": 2,
            "disabled_reason": "out_of_credits",
            "user_disabled": false,
            "spend_limit_reached": false,
            "credits_ever_enabled": true,
            "daily": null,
            "weekly": null
        },
        "limits": [
            {
                "kind": "session",
                "group": "session",
                "percent": 9,
                "severity": "normal",
                "resets_at": "2026-08-21T21:49:59.960275+00:00",
                "scope": null,
                "is_active": false
            },
            {
                "kind": "weekly_all",
                "group": "weekly",
                "percent": 75,
                "severity": "warning",
                "resets_at": "2026-08-23T04:59:59.960293+00:00",
                "scope": null,
                "is_active": true
            },
            {
                "kind": "weekly_scoped",
                "group": "weekly",
                "percent": 75,
                "severity": "warning",
                "resets_at": "2026-08-23T04:59:59.960482+00:00",
                "scope": {
                    "model": {
                        "id": null,
                        "display_name": "Fable"
                    },
                    "surface": null
                },
                "is_active": false
            }
        ],
        "spend": {
            "used": {
                "amount_minor": 1221,
                "currency": "EUR",
                "exponent": 2
            },
            "limit": null,
            "percent": 0,
            "severity": "normal",
            "enabled": false,
            "disabled_reason": "out_of_credits",
            "cap": null,
            "balance": null,
            "auto_reload": null,
            "disclaimer": "Usage credits cover you when you hit your plan limits.",
            "can_purchase_credits": false,
            "can_toggle": false
        },
        "member_dashboard_available": false
    }
    """#
}
