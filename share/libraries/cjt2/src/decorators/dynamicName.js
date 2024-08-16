/*
# cjt/decorators/dynamicName.js                  Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.decorators.dynamicName", []);

        // Workaround for bug #1404
        // https://github.com/angular/angular.js/issues/1404
        // Source: http://plnkr.co/edit/hSMzWC?p=preview
        module.config(["$provide", function($provide) {

            // Extend the ngModelDirective to interpolate its name attribute
            $provide.decorator("ngModelDirective", ["$delegate", function($delegate) {
                var ngModel = $delegate[0], controller = ngModel.controller;
                ngModel.controller = ["$scope", "$element", "$attrs", "$injector", function(scope, element, attrs, $injector) {
                    var $interpolate = $injector.get("$interpolate");
                    attrs.$set("name", $interpolate(attrs.name || "")(scope));
                    $injector.invoke(controller, this, {
                        "$scope": scope,
                        "$element": element,
                        "$attrs": attrs
                    });
                }];
                return $delegate;
            }]);

            // Extend the formDirective to interpolate its name attribute
            $provide.decorator("formDirective", ["$delegate", function($delegate) {
                var form = $delegate[0], controller = form.controller;
                form.controller = ["$scope", "$element", "$attrs", "$injector", function(scope, element, attrs, $injector) {
                    var $interpolate = $injector.get("$interpolate");
                    attrs.$set("name", $interpolate(attrs.name || attrs.ngForm || "")(scope));
                    $injector.invoke(controller, this, {
                        "$scope": scope,
                        "$element": element,
                        "$attrs": attrs
                    });
                }];
                return $delegate;
            }]);
        }]);
    }
);
