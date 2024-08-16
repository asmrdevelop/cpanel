/*
# templates/hulkd/directives/disableValidation.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
  * @summary Directive that disables any validation functions tied to an ngModel
  * based on a value (which must be evaluated) passed to the directive.
  *
  * This code is based on this plunkr: https://embed.plnkr.co/EM1tGb/
  *
  * @required ngModel This directive requires ngModel be set on the element.
  *
  * @example
  * <input type="text"
  *     id="theText"
  *     name="theText"
  *     ng-model="myvalue"
  *     required
  *     disable-validation="toggleValidation">
  */
define(
    [
        "angular"
    ],
    function(angular) {
        "use strict";

        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", []);
        }

        app.directive("disableValidation", function() {
            return {
                require: "ngModel",
                restrict: "A",
                link: function(scope, element, attrs, ngModelController) {
                    var originalValidators = angular.copy(ngModelController.$validators);
                    Object.keys(originalValidators).forEach(function(key) {
                        ngModelController.$validators[key] = function(v) {

                            // pass the view value twice because some validators take modelValue and viewValue (e.g. required)
                            return scope.$eval(attrs.disableValidation) || originalValidators[key](v, v);
                        };
                    });

                    scope.$watch(attrs.disableValidation, function() {

                        // trigger validation
                        var originalViewValue = ngModelController.$viewValue;
                        scope.$applyAsync(function() {
                            ngModelController.$setViewValue("");
                            ngModelController.$setViewValue(originalViewValue);
                        });
                    });

                }
            };
        });
    }
);
