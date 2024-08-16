/*
# cjt/directives/autoFocus.js                     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// ------------------------------------------------------------
// Developer notes:
// ------------------------------------------------------------
// The concept for this construct was derived from:
// http://stackoverflow.com/questions/14859266/input-autofocus-attribute
// http://jsfiddle.net/ANfJZ/39/
// Used with permission.
// ------------------------------------------------------------

define(
    [
        "angular"
    ],
    function(angular) {

        var module = angular.module("cjt2.directives.autoFocus", []);

        /**
         * Directive that triggers the filed to be auto-focused on load.
         * @example
         *
         * Always auto-focus the field:
         * <input auto-focus />
         *
         * Conditionally focus the field based on the state variable.
         * <input auto-focus="condition" />
         *
         * Call lost focus callback on focus lost.
         * <input auto-focus onFocusLost="handleFocusLost()" />
         */
        module.directive("autoFocus", [ "$timeout", function($timeout) {
            return {
                link: function( scope, element, attrs ) {

                    // Watch for changes in the attribute, triggered at view load time too.
                    scope.$watch( attrs.autoFocus, function( val ) {

                        // only trigger the autofocus if we have a condition and it's true or if we have no condition at all
                        var condition_exists_and_is_true = angular.isDefined(val) && val;
                        if (angular.isDefined(attrs.autoFocus) &&
                            ((attrs.autoFocus === "") || (attrs.autoFocus !== "" && condition_exists_and_is_true)) ) {
                            $timeout( function() {
                                element[0].focus();
                            } );
                        }
                    }, true);

                    element.bind("blur", function() {
                        if ( angular.isDefined( attrs.onFocusLost ) ) {
                            scope.$apply( attrs.onFocusLost );
                        }
                    });
                }
            };
        }]);
    }
);
