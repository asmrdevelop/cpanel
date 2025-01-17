/*
# mail/spam/views/ROUTES.js                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "cjt/util/locale"
    ],
    function(LOCALE) {

        "use strict";

        var ROUTES = [
            {
                "id": "atAGlance",
                "route": "/overview",
                "hideTitle": true,
                "controller": "atAGlance",
                "templateUrl": "views/atAGlance.ptt",
                "title": LOCALE.maketext("Overview"),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }]
                }
            },
            {
                "id": "spamBox",
                "route": "/spambox",
                "controller": "spamBox",
                "parentRoute": "atAGlance",
                "templateUrl": "views/spamBox.ptt",
                "title": LOCALE.maketext("Spam Box"),
                "description": LOCALE.maketext("Spam Box will deliver any emails that the system identifies as spam into a separate mail folder named [output,em,spam]."),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }]
                }
            },
            {
                "id": "requiredScore",
                "route": "/required-score",
                "controller": "configurations",
                "parentRoute": "atAGlance",
                "templateUrl": "views/requiredScore.ptt",
                "title": LOCALE.maketext("Adjust Spam Threshold Score"),
                "description": (
                    LOCALE.maketext("Configure the [asis,Spam Score Threshold].") +
                    " " +
                    LOCALE.maketext("If your hosting provider enables rewrites, the server will add a “***SPAM***” tag to the subject when the message’s calculated spam score meets or exceeds the Spam Threshold Score.")
                ),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }]
                }
            },
            {
                "id": "spamAutoDelete",
                "route": "/autodelete",
                "controller": "spamAutoDelete",
                "parentRoute": "atAGlance",
                "templateUrl": "views/spamAutoDelete.ptt",
                "title": LOCALE.maketext("Auto-Delete"),
                "description": LOCALE.maketext("Automatically delete messages with spam scores that meet or exceed the Auto-Delete Threshold Score. The Auto-Delete Threshold Score does not affect the Spam Threshold Score."),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }]
                }
            },
            {
                "id": "whitelist",
                "route": "/whitelist",
                "controller": "configurations",
                "parentRoute": "atAGlance",
                "templateUrl": "views/whitelist.ptt",
                "title": LOCALE.maketext("Whitelist"),
                "description": LOCALE.maketext("Configure the whitelist settings for Spam Filters."),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }]
                }
            },
            {
                "id": "blacklist",
                "route": "/blacklist",
                "controller": "configurations",
                "parentRoute": "atAGlance",
                "templateUrl": "views/blacklist.ptt",
                "title": LOCALE.maketext("Blacklist"),
                "description": LOCALE.maketext("Configure the blacklist settings for Spam Filters."),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }]
                }
            },
            {
                "id": "advanced",
                "route": "/advanced-settings",
                "controller": "configurations",
                "parentRoute": "atAGlance",
                "templateUrl": "views/advancedSettings.ptt",
                "title": LOCALE.maketext("Calculated Spam Score Settings"),
                "description": LOCALE.maketext("Configure the calculated spam score settings."),
                "resolve": {
                    "userPreferences": ["spamAssassin", function($service) {
                        return $service.getUserPreferences();
                    }],
                    "spamTestingSymbolicNames": ["spamAssassin", function($service) {
                        return $service.getSymbolicTestNames();
                    }]
                }
            }
        ];

        return ROUTES;
    }
);
