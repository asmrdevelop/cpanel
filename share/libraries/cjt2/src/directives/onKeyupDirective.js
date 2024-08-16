/*
# cjt/directives/onKeyupDirective.js              Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        var module = angular.module("cjt2.directives.onKeyUp", []);

        module.directive("cpKeyup", function() {
            return {
                restrict: "A",
                scope: {
                    callback: "&cpKeyupAction"
                },
                link: function(scope, elm, attrs) {

                    // Determine the keys we are filtering on if any
                    var allowedKeys = scope.$eval(attrs.cpKeyupKeys);

                    elm.bind("keyup", function(evt) {
                        if (!allowedKeys || allowedKeys.length === 0) {

                            // Callback all the time
                            scope.callback(evt.which);
                        } else {
                            angular.forEach(allowedKeys, function(key) {

                                // Callback only if the key is in the filter set
                                if (key === evt.which) {
                                    scope.callback(evt.which);
                                }
                            });
                        }
                    });
                }
            };
        });
    }
);
