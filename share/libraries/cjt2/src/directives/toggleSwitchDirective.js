/*
# cjt/directives/toggleSwitchDirective.js                                        Copyright(c) 2020 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/test",
        "uiBootstrap",
        "cjt/directives/spinnerDirective",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, _, CJT, TEST) {

        "use strict";

        var module = angular.module("cjt2.directives.toggleSwitch", [
            "cjt2.templates",
            "cjt2.directives.spinner"
        ]);

        /**
         * Directive that renders a toggle switch
         * @attribute {String}  id -
         * @attribute {String}  enabledLabel
         * @attribute {String}  disabledLabel
         * @attribute {String}  labelPosition - one of right, left, none
         * @attribute {String}  spinnerPosition - one of right, left
         * @attribute {Boolean} noSpinner - true or false, if true will suppress the spinner.
         * @attribute {String}  ariaLabel
         * @attribute {Binding} ngDisabled
         * @attribute {Binding} ngModel - required
         * @attribute {Function} onToggle - required to make the switch toggle on click. You must provide this and it
         * must handle the needed state change to trigger a toggle effect.
         * @example
         * <toggle-switch ng-model="state" on-toggle="state = !state" />
         */
        module.directive("toggleSwitch", ["spinnerAPI",
            function(spinnerAPI) {

                var RELATIVE_PATH = "libraries/cjt2/directives/toggleSwitch.phtml";


                return {
                    restrict: "E",
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    require: "ngModel",
                    replace: true,
                    scope: {
                        parentID: "@id",
                        enabledLabel: "@",
                        disabledLabel: "@",
                        labelPosition: "@",
                        spinnerPosition: "@",
                        ariaLabel: "@",
                        isDisabled: "=ngDisabled",
                        ngModel: "=",
                        onToggle: "&",
                    },
                    link: function(scope, elem, attrs) {

                        scope.noSpinner = attrs.noSpinner === "true" || attrs.noSpinner === "1";
                        scope.spinnerId = scope.parentID + "_toggle_spinner";
                        if (!scope.labelPosition) {
                            scope.labelPosition = "right"; // To preserve behavior that existed
                        } else if (!_.includes(["left", "right", "none"], scope.labelPosition)) {
                            throw "Invalid label-position set: " + scope.labelPosition + ". Must be one of: left, right, none.";
                        }

                        if (!scope.spinnerPosition) {
                            scope.spinnerPosition = "right"; // To preserve behavior that existed
                        } else if (!_.includes(["left", "right"], scope.spinnerPosition)) {
                            throw "Invalid label-position set: " + scope.spinnerPosition + ". Must be one of: left or right.";
                        }

                        scope.noLabel = (!scope.enabledLabel && !scope.disabledLabel) || scope.labelPosition === "none";

                        scope.handle_keydown = function(event) {

                            // prevent the spacebar from scrolling the window
                            if (event.keyCode === 32) {
                                event.preventDefault();
                            }
                        };

                        scope.handle_keyup = function(event) {

                            // bind to the spacebar and enter keys to toggle the field
                            if (event.keyCode === 32 || event.keyCode === 13) {
                                event.preventDefault();
                                scope.toggle_status();
                            }

                            // bind left arrow to turn off
                            if (event.keyCode === 37) {
                                event.preventDefault();
                                if (scope.ngModel) {
                                    scope.toggle_status();
                                }
                            }

                            // bind right arrow to turn on
                            if (event.keyCode === 39) {
                                event.preventDefault();
                                if (!scope.ngModel) {
                                    scope.toggle_status();
                                }
                            }
                        };

                        scope.get_aria_value = function() {
                            return scope.ngModel ? "true" : "false";
                        };

                        /**
                         * Start the spinner if needed
                         */
                        var _startSpinner = function() {
                            if (!scope.noSpinner) {
                                spinnerAPI.start(scope.spinnerId, false);
                            }
                        };

                        /**
                         * Stop the spinner if needed
                         */
                        var _stopSpinner = function() {
                            if (!scope.noSpinner) {
                                spinnerAPI.stop(scope.spinnerId, false);
                            }
                        };

                        scope.toggle_status = function() {
                            if (scope.changing_status || scope.isDisabled) {
                                return;
                            }

                            scope.changing_status = true;
                            _startSpinner();

                            var promise = scope.onToggle();
                            if (TEST.isQPromise(promise)) {
                                promise.finally(function() {
                                    scope.changing_status = false;
                                    _stopSpinner();
                                });
                            } else {
                                scope.changing_status = false;
                                _stopSpinner();
                            }
                        };
                    }
                };
            }
        ]);
    }
);
