/*
# cjt/directives/limitRange.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "lodash"
    ],
    function(angular, CJT, _) {

        // Constants
        var SCOPE_DECLARATION = {
            rangeMinimum: "@rangeMinimum",
            rangeMaximum: "@rangeMaximum",
            rangeDefault: "@rangeDefault"
        };

        var module = angular.module("cjt2.directives.limitRange", []);

        /**
         * Directive that prevents numeric inputs from going outside an integer range.
         * @attribute {Number}  rangeMinimum - minimum value allowed.
         * @attribute {Number}  rangeMaximum - maximum value allowed.
         * @attribute {Number}  rangeDefault - default value to us if the field is invalid.
         * @example
         * <input limit-range range-minimum="1" range-maximum="10" />
         */
        module.directive("limitRange", [ function() {
            return {
                restrict: "A",
                require: "?ngModel",
                scope: SCOPE_DECLARATION,
                link: function(scope, element, attrs, model) {

                    /* Apply range restrictions on blur. This is better than trying to apply them
                     * immediately because a partially-typed number might fall outside of the allowable
                     * range, causing unexpected behavior. */
                    element.bind("blur", function(e) {

                        var minimum = _parseIntOrDefault(scope.rangeMinimum, null);
                        var maximum = _parseIntOrDefault(scope.rangeMaximum, null);

                        if (!this.value) {
                            this.value = _parseIntOrDefault(scope.rangeDefault, 1);
                        }

                        if (minimum !== null) {
                            if (this.value < minimum) {
                                this.value = minimum;
                            }
                        }

                        if (maximum !== null) {
                            if (this.value > maximum) {
                                this.value = maximum;
                            }
                        }

                        _update(model, this.value);
                    });

                    // Only allow the navigation keys and the number keys
                    // Key code reference: https://css-tricks.com/snippets/javascript/javascript-keycodes/
                    element.on("keydown", function(event) {

                        // Cursor movements and delete/backspace
                        if (_.includes([
                            8,  // backspace
                            9,  // tab
                            13, // return/enter
                            33, // page up
                            34, // page down
                            35, // end
                            36, // home
                            37, // left arrow
                            38, // up arrow
                            39, // right arrow
                            40, // down arrow
                            45, // insert - can be used for cut/paste
                            46  // delete
                        ], event.keyCode)) {
                            return true;
                        }

                        // Numbers, both keypad and main number keys.
                        if ((event.keyCode >= 48 && event.keyCode <= 57) || (event.keyCode >= 96 && event.keyCode <= 105)) {
                            return true;
                        }

                        // Cut and paste: CTRL-c, CTRL-v, CTRL-x
                        if ((event.ctrlKey || event.metaKey) && (event.keyCode === 67 || event.keyCode === 86 || event.keyCode === 88)) {
                            return true;
                        }

                        // Otherwise, cancel the event
                        event.preventDefault();
                        return false;
                    });
                }
            };
        }]);

        /**
         * Parse the string as an integer. If it does not return a number, use the default instead.
         * @param  {String} string
         * @param  {Number} defaultValue
         * @return {Number}
         */
        function _parseIntOrDefault(string, defaultValue) {
            var parsed = parseInt(string, 10); // parseInt returns NaN with undefined, null, or empty strings
            return isNaN(parsed) ? defaultValue : parsed;
        }

        /**
         * If the model exists, update the model with the dynamically set value and revalidate.
         * @param  {Object} model
         * @param  {Any} value
         */
        function _update(model, value) {
            if (model) {
                model.$setViewValue(value);
                model.$validate();
            }
        }

    });
