/*
# cjt/decorators/growlAPIReporter.js              Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* One possible display-layer complement to the APICatcher service. This
   module will display all failures from APICatcher in the UI via growl
   notifications and the browser console.

   It is assumed (for now) that this is as simple as just showing the
   response’s .error value; for batch responses, we probably want to be
   more detailed eventually (TODO).

   Ultimately, we’d ideally even create *typed* failure response objects;
   these could encapsulate their own logic for generating a string (or
   even raw markup??) to report failures.

   See APICatcher for more information.
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/services/APIFailures",
        "cjt/decorators/growlDecorator",
    ],
    function(angular, _) {

        "use strict";

        // Set up the module in the cjt2 space
        var module = angular.module("cjt2.decorators.growlAPIReporter", ["cjt2.decorators.growlDecorator"]);

        module.config(["$provide", function($provide) {
            $provide.decorator("growl", ["$delegate", "APIFailures", "$log", function(growl, apifail, $log) {
                function _reportMessages(messages) {
                    messages.forEach(function(message) {
                        $log.warn(message.content);

                        if (message.type === "danger") {
                            return growl.error(_.escape(message.content));
                        } else if (message.type === "warning") {
                            return growl.warning(_.escape(message.content));
                        }
                    });
                }

                apifail.register(_reportMessages);

                return growl;
            }]);
        }]);
    }
);
