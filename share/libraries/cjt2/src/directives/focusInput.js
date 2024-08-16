/*
# cjt/directives/focusInput.js                    Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.directives.focusInput", []);

        module.directive("focusInput", ["$timeout", function($timeout) {
            return {
                link: function(scope, element, attrs) {
                    element.bind("click", function() {
                        $timeout(function() {
                            element.parent().parent().find("input")[0].focus();
                        });
                    });
                }
            };
        }]);
    }
);
