/*
 * templates/multiphp_manager/directives/nonStringSelect.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                    All rights reserved.
 * copyright@cpanel.net                                                  http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
    ],
    function(angular) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.directive("convertToNumber", function() {
            return {
                require: "ngModel",
                link: function(scope, element, attrs, ngModel) {
                    ngModel.$parsers.push(function(val) {
                        return parseInt(val, 10);
                    });
                    ngModel.$formatters.push(function(val) {
                        return "" + val;
                    });
                }
            };
        });

        return controller;
    }
);
