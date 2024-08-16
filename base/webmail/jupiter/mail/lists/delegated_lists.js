/*
# cpanel - base/webmail/jupiter/mail/lists/delegated_lists.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    [
        "angular",
        "cjt/modules",
    ],
    function(angular) {
        "use strict";

        var app = angular.module("App", ["ui.bootstrap", "cjt2.webmail"]);

        /*
         * this looks funky, but these require that
         * angular be loaded before they can be loaded
         * so the nested requires become relevant
         */
        app = require(
            [
                "cjt/directives/toggleSortDirective",
                "cjt/directives/spinnerDirective",
                "cjt/directives/searchDirective",
                "cjt/directives/pageSizeDirective",
                "app/services/mailingListsService",
                "app/controllers/mailingListsController",
                "app/controllers/mainController",
                "uiBootstrap",
            ],
            function() {

                var app = angular.module("App");

                // app.config(["$provide", Decorate]);

                /*
                 * filter used to escape emails and urls
                 * using native js escape
                 */
                app.filter("escape", function() {
                    return window.escape;
                });

                /*
                 * because of the race condition with the dom loading and angular loading
                 * before the establishment of the app
                 * a manual initiation is required
                 * and the ng-app is left out of the dom
                 */
                app.init = function() {
                    var appContent = angular.element("#content");

                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        angular.bootstrap(appContent[0], ["App"]);
                    }

                    return app;
                };
                app.init();
            });

        return app;
    }
);
