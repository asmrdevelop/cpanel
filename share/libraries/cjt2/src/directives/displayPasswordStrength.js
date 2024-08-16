/*
# cjt/directives/displayPasswordStrength.js       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        var RELATIVE_PATH = "libraries/cjt2/directives/displayPasswordStrength.phtml";

        var DEFAULT_STYLES = [
            "strength-0",
            "strength-1",
            "strength-2",
            "strength-3",
            "strength-4"
        ];

        var module = angular.module("cjt2.directives.displayPasswordStrength", [
            "cjt2.templates"
        ]);

        /**
         * Directive that shows the password strength in a meter bar.
         * @attribute [fieldId] Optional field id, used to correlate the message from the strength service. Not needed
         * if only one password strength field is used on the view.
         * @attribute [styles]  Optional comma delimited list of css class names for the colors. Must be 4 items in the
         * list or the directive will use the defaults.
         * @attribute [calculateColorBreak] Optional function to process the strength increment process. The function should return
         * a structure with the following layout:
         *   {
         *       index: <number>,  // Number 1 to 5 for the slot to fill too.
         *       color: <string>   // CSS class name to use to do the fill for slots 1 to index.
         *   }
         * If not provided, the built in function uses a step-wise linear algorithm breaking every 20 units for 0 to 100.
         * @example
         *
         * <div displayPasswordStrength></div>
         */
        module.directive("displayPasswordStrength", function() {
            return {
                replace: true,
                restrict: "EACM",
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                scope: {
                    fieldId: "@?fieldId",
                    styles: "@?styles",
                    calculateColorBreak: "&calculateColorBreak"
                },
                compile: function(element, attrs) {
                    return {
                        pre: function(scope, element, attrs) {
                            if (!angular.isUndefined(attrs.styles)) {
                                var styles = (attrs.styles + "").split(",");
                                if (styles.length < 5) {
                                    throw "You must provide a list of 5 css class names if you are implementing custom styles";
                                } else {
                                    scope.styles = styles;
                                }
                            }
                        },

                        post: function(scope, el, attrs) {
                            var colors = scope.styles && scope.styles.length === 5 ? scope.styles : DEFAULT_STYLES;
                            var allClasses = colors.join(" ");

                            /**
                             * Get the color related to the indicated password strength. This is the
                             * default implementation. User can override this behavior with their own
                             * method.
                             *
                             * @private
                             * @method calculateColorBreak
                             * @param  {Number} strength - current strength
                             * @param  {Array}  colors - list of css class names
                             * @return {Object}
                             *   {Number} index Position to update: 1 to 5.
                             *   {String} color Color to use with this strength.
                             */
                            var _calculateColorBreak  = function(strength, colors) {
                                var index = 0;
                                if (strength <= 20) {
                                    index = 0;
                                } else if (strength <= 40) {
                                    index = 1;
                                } else if (strength <= 60) {
                                    index = 2;
                                } else if (strength <= 80) {
                                    index = 3;
                                } else {
                                    index = 4;
                                }

                                return {
                                    index: index + 1,
                                    color: colors[index]
                                };
                            };


                            if (scope.calculateColorBreak) {
                                scope.calculateColorBreak = _calculateColorBreak;
                            }

                            // Monitor for the passwordStrengthChange event
                            scope.$on("passwordStrengthChange", function(evt, result) {
                                if ( !angular.isUndefined(scope.fieldId) && scope.fieldId !== result.id ) {

                                    // This is not for us since its a
                                    // message not related to our caller.
                                    return;
                                }

                                var hasPassword = result.hasPassword;
                                var strength = result.strength;

                                if (!hasPassword) {
                                    el.children("li")
                                        .removeClass(allClasses);
                                } else {
                                    var colorBreak = scope.calculateColorBreak(strength, colors);
                                    el.children("li")
                                        .removeClass(allClasses)
                                        .slice(0, colorBreak.index)
                                        .addClass(colorBreak.color);
                                }
                            });
                        }
                    };
                }
            };
        });

        return {
            DEFAULT_STYLES: DEFAULT_STYLES
        };
    }
);
