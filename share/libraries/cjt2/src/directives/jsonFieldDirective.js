/*
# cjt/directives/jsonFieldDirective.js            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/**
 * @module cjt/directives/jsonFieldDirective
 */
define(
    [
        "angular",
        "cjt/core"
    ],
    function(angular, CJT) {
        var module = angular.module("cjt2.directives.jsonFieldDirective", []);
        module.directive("jsonField", [ "$document", "$compile", function($document, $compile) {
            return {
                restrict: "E",
                scope: {
                    model: "="
                },
                link: function(scope, element, attrs) {
                    if ( angular.isDefined(scope.model) ) {
                        var model = scope.model,
                            newElement;

                        model.type = model.type.toLowerCase();

                        if ( angular.isDefined(model.type) && model.type === "textarea" ) {
                            newElement = $document[0].createElement(model.type);
                        } else {
                            newElement = $document[0].createElement("input");
                        }
                        newElement = angular.element(newElement);

                        if ( !angular.isDefined(model.name) && angular.isDefined(model.id) ) {
                            model.name = model.id;
                        }

                        if ( model.type.indexOf("date", 0) === 0 ) {

                            // convert the value to a date object
                            model.value = new Date(model.value);
                        }

                        if ( model.type !== "range" && model.type !== "color" &&
                            model.type !== "checkbox" && model.type !== "radio" ) {
                            newElement.attr("class", "form-control");
                        }

                        if ( model.type === "checkbox" ) {
                            newElement.attr("ng-true-value", "'true'");
                            newElement.attr("ng-false-value", "'false'");
                        }

                        if ( !angular.isDefined(model.value) ) {
                            model.value = "";
                        }
                        newElement.attr("ng-model", attrs.model + ".value");

                        angular.forEach(model, function(value, key) {
                            if ( key === "type" && value !== "textarea" || key !== "value" ) {
                                try {
                                    newElement.attr(key, value);
                                } catch (e) {
                                    if ( key !== "$$hashKey") {

                                        // throw an exception on invalid keys
                                        throw (e);
                                    }
                                }
                            }
                        });

                        newElement = $compile(newElement)(scope.$parent);
                        element.replaceWith(newElement);
                    }
                }
            };
        }]);
    }
);
