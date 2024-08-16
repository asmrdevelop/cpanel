/*
# cjt/decorators/alertAPIReporter.js              Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* One possible display-layer complement to the APICatcher service. This
   module will display all failures from APICatcher in the UI via alert
   notifications and the browser console.

   It is assumed (for now) that this is as simple as just showing the
   response’s .error value; for batch responses, we probably want to be
   more detailed eventually (TODO).

   Ultimately, we’d ideally even create *typed* failure response objects;
   these could encapsulate their own logic for generating a string (or
   even raw markup??) to report failures.

   You’ll need the following somewhere in the ng template where this
   logic can find it:

        <cp-alert-list></cp-alert-list>

   See APICatcher for more information.
 */

/* global define: false */

define(
    [
        "angular",
        "cjt/services/APIFailures",
        "cjt/services/alertService",
    ],
    function(angular, _) {

        "use strict";

        // Set up the module in the cjt2 space
        var module = angular.module("cjt2.decorators.alertAPIReporter", ["cjt2.services.alert"]);

        module.config(["$provide", function($provide) {
            $provide.decorator("alertService", ["$delegate", "APIFailures", "$log", function(alertService, apifail, $log) {
                function _reportMessages(messages) {
                    messages.forEach(function(message) {
                        $log.warn(message.content);

                        alertService.add( {
                            type: message.type,
                            message: message.content,
                            replace: false
                        } );
                    });

                }

                apifail.register(_reportMessages);

                return alertService;
            }]);
        }]);
    }
);
