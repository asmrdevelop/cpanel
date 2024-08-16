/*
# directives/indeterminateState.js                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
define(["angular"],
    function(angular) {
        "use strict";

        var module = angular.module("cjt2.directives.indeterminateState", []);

        function SetIndeterminateState() {
            return {
                restrict: "A",
                scope: {
                    checkState: "&"
                },
                link: function(scope, element) {
                    scope.$watch(scope.checkState, function(newValue) {
                        element.prop("indeterminate", newValue);
                    });
                }
            };
        }

        module.directive("indeterminateState", SetIndeterminateState);
    }
);
