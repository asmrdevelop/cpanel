/*
 * user_manager/directives/modelToLowerCase.js     Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
    ],
    function(angular) {

        /**
         * This directive simply adds a parser to transform input into lowercase before saving it to the model.
         *
         * Example: <input ng-model="myModel" model-to-lower-case>
         */
        angular.module("App").directive("modelToLowerCase", [
            function() {

                return {
                    restrict: "A",
                    require: "ngModel",
                    link: function(scope, elem, attrs, ngModel) {
                        ngModel.$parsers.unshift(function(viewVal) {
                            return viewVal.toLocaleLowerCase();
                        });
                    }
                };
            }
        ]);
    }
);
