/*
# cjt/decorators/growlDecorator.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "angular-growl",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        // Set up the module in the cjt2 space
        var module = angular.module("cjt2.decorators.growlDecorator", ["angular-growl"]);

        module.config(["$provide", function($provide) {

            // make the growl use our template
            $provide.decorator("growlDirective", ["$delegate", function($delegate) {
                var RELATIVE_PATH = "libraries/cjt2/directives/growl.phtml";
                var ngGrowlDirective = $delegate[0];

                // use our template
                ngGrowlDirective.templateUrl = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

                return $delegate;
            }]);

            // add ids to the growl messages
            $provide.decorator("growlMessages", ["$delegate", function($delegate)  {
                var counter = 0;
                var PREFIX = "growl_";

                // save the original addMessage call
                var addMessageFn = $delegate.addMessage;

                var addId = function() {
                    var args = [].slice.call(arguments);

                    // first arg should have the message object
                    // add a unique id to the messge object
                    args[0].id = PREFIX + args[0].referenceId + "_" + (++counter);

                    // call the original addMessage function and pass the service object as 'this'
                    return addMessageFn.apply($delegate, args);
                };

                $delegate.addMessage = addId;

                return $delegate;
            }]);

        }]);
    }
);
