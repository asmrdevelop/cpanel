/*
# cpanel - templates/transfer_tool/getacctlist.js  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require:false, define:false, confirm:false, alert:false, PAGE, EVENT:true */

(function(window) {
    "use strict";

    var enterSessionIfNotPending = function() {
        CPANEL.api({
            "func": "get_transfer_session_state",
            "data": {
                "transfer_session_id": PAGE.transfer_session_id
            },
            "callback": {
                success: function(o) {
                    var response = o.cpanel_data;
                    var statename = response.state_name;

                    if (o.cpanel_error) {
                        alert(LOCALE.maketext("Failed to retrieve the session state: [_1]", o.cpanel_error));
                    } else if (statename) {
                        if (statename !== "PENDING") {
                            if (confirm(LOCALE.maketext("The session has already started and cannot accept additional inputs. Would you like to view the transfer session?"))) {
                                window.location.href = "transfer_session?transfer_session_id=" + encodeURIComponent(PAGE.transfer_session_id);
                            } else {
                                window.history.go(-1);

                                /* Don't let them enter data on the screen as it will screen as it will just fail on the next screen since it the transfer sessions is already in progress */
                            }
                        }
                    }
                },
                failure: function() {
                    alert(LOCALE.maketext("Failed to retrieve the session state."));
                }
            }
        });
    };

    var reAnalyzeRemote = function() {
        var reAnalyzeRemoteButton = CPANEL.Y.one("#reAnalyzeRemoteButton"),
            preChangeText = reAnalyzeRemoteButton.innerHTML;

        reAnalyzeRemoteButton.disabled = true;
        reAnalyzeRemoteButton.innerHTML = "<i class='glyphicon glyphicon-refresh animate-spin'></i> " + LOCALE.maketext("Performing Analysis …");

        CPANEL.api({
            func: "analyze_transfer_session_remote",
            data: {
                "transfer_session_id": PAGE.transfer_session_id
            },
            callback: CPANEL.ajax.build_page_callback(function() {
                window.location.href = "transfer_selection?transfer_session_id=" + encodeURIComponent(PAGE.transfer_session_id);
            }, {
                pagenotice_container: "callback_block",
                on_error: function() {
                    reAnalyzeRemoteButton.disabled = false;
                    reAnalyzeRemoteButton.innerHTML = preChangeText;
                }
            })
        });
    };

    var init = function() {
        EVENT.on(CPANEL.Y.one("#reAnalyzeRemoteButton"), "click", reAnalyzeRemote);
        enterSessionIfNotPending();

        // Parse Blocker Data for Easy Apache
        if (PAGE.configuration_modules.Apache.analysis) {
            PAGE.EABlockers = PAGE.configuration_modules.Apache.analysis["Blocker Data"];

            // Loop through each item, look for Blocker level item
            for (var i = PAGE.EABlockers.length - 1; i >= 0; i--) {
                if (PAGE.EABlockers[i].vendor_id === "Cpanel" && PAGE.EABlockers[i].items) {
                    for (var j = PAGE.EABlockers[i].items.length - 1; j >= 0; j--) {
                        if (PAGE.EABlockers[i].items[j].status === 2) {
                            PAGE.blockerExists = true;
                        }
                    }
                }
            }
        }
    };

    EVENT.onDOMReady(init);


})(window);

/* angular portion */

define(
    [
        "angular",
        "app/directives/accountExpandPanel",
        "cjt/util/locale",
        "app/overwriteStates",
        "app/overwriteOptions",
        "jquery",
        "ngRoute",
        "uiBootstrap",
        "angular-chosen",
        "ngSanitize",
        "cjt/modules",
        "cjt/directives/toggleLabelInfoDirective",
    ],
    function(angular, AccountExpandPanel, LOCALE, OVERWRITE_STATES, OVERWRITE_OPTIONS) {
        "use strict";

        return function() {
            var app = angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "cjt2.whm",
                "ngSanitize",
                "ui.bootstrap",
                AccountExpandPanel.namespace
            ]);

            app.value("OVERWRITE_DESCRIPTION_TEMPLATE", "overwriteWithDeleteDescription.ptt");
            app.value("OVERWRITE_STATES", OVERWRITE_STATES);
            app.value("OVERWRITE_OPTIONS", OVERWRITE_OPTIONS);

            app.value("LOCAL_WORKER_NODES", PAGE.local.linked_nodes);
            app.value("REMOTE_WORKER_NODES", PAGE.remote.linked_nodes);

            return require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/controllers/MainController",
                    "app/controllers/AccountTableController",
                    "app/directives/boolToIntDirective",
                    "app/directives/ngDebounceDirective",
                    "app/directives/preventBubblingDirective",
                    "cjt/directives/pageSizeDirective",
                    "app/directives/clickOnceDirective",
                    "app/filters/overwriteFilter",
                    "app/filters/bytesFilter"
                ], function(BOOTSTRAP) {

                    BOOTSTRAP(document);
                });
        };
    }
);
