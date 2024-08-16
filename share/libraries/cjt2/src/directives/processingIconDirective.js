/*
** app/directives/processingIconDirective.js
**                                                 Copyright(c) 2020 cPanel, L.L.C.
**                                                           All rights reserved.
** copyright@cpanel.net                                         http://cpanel.net
** This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, LOCALE) {

        var module = angular.module("cjt2.directives.processingIcon", [
            "cjt2.templates"
        ]);

        var states = {
            default: 0,
            run: 1,
            done: 2,
            error: 3,
            unknown: 4
        };

        var validStates = [
            states.default,
            states.run,
            states.done,
            states.error,
            states.unknown
        ];

        module.constant("processingIconStates", states);

        var state_lookup = [
            "default",
            "run",
            "done",
            "error",
            "unknown"
        ];

        /**
         * Directive that shows a processing icon in the correct state.
         *
         * @property {String} [defaultTitle] Override title for the default state.
         * @property {String} [doneTitle] Override title for the done state.
         * @property {String} [errorTitle] Override title for the error state.
         * @property {String} [runTitle] Override title for the run state.
         * @property {String} [unknownTitle] Override title for the unknown state.
         * @property {Model}  [ngModel] Model controlling which state the processing
         *                              icon is in. It can be one of the following:
         *                                0 - default state
         *                                1 - running state
         *                                2 - done state
         *                                3 - error state
         *                                4 - unknown state
         * @example
         *
         * Example of a single processing icon:
         *
         * <span cp-processing-icon ng-model="state"></span>
         *
         * @example
         *
         * Example of multiple processing icon with descriptions:
         *
         * var tasks = [
         *     { name: "Task 1", state: processingIconStates.run },
         *     { name: "Task 2", state: processingIconStates.default },
         *     { name: "Task 3", state: processingIconStates.done },
         * ];
         *
         * <div>
         *   <span cp-processing-icon ng-model="task[0].state"></span>
         *   <span>Performing {{tasks[0].name}}</span>
         * </div>
         * <div>
         *   <span cp-processing-icon ng-model="task[1].state"></span>
         *   <span>Performing {{tasks[1].name}}</span>
         * </div>
         * <div>
         *   <span cp-processing-icon ng-model="task[2].state"></span>
         *   <span>Performing {{tasks[2].name}}</span>
         * </div>
         */
        module.directive("cpProcessingIcon", ["processingIconStates",
            function(processingIconStates) {
                var RELATIVE_PATH = "libraries/cjt2/directives/processingIcon.phtml";

                var TITLES = {
                    default: "",
                    run: LOCALE.maketext("Running"),
                    done: LOCALE.maketext("Done"),
                    error: LOCALE.maketext("Error"),
                    unknown: LOCALE.maketext("Unknown"),
                };

                return {
                    restrict: "A",
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    replace: true,
                    require: "ngModel",
                    scope: {
                        defaultTitle: "@",
                        runTitle: "@",
                        doneTitle: "@",
                        errorTitle: "@",
                        unknownTitle: "@"
                    },
                    compile: function(element, attrs) {

                        // Initialize any labels not provided
                        angular.forEach(TITLES, function(value, key) {
                            var attrName = key + "Title";
                            if (!angular.isDefined(attrs[attrName])) {
                                attrs[attrName] = value;
                            }
                        });

                        return function(scope, element, attrs, ngModelCtrl) {

                            /**
                             * Lookup the title for the state on the scope.
                             * @param  {Number} state Numeric representation of the state.
                             * @return {String}       Title for the state icon.
                             */
                            var lookupTitle = function(state) {
                                var stateName = state_lookup[state];
                                var attrName = stateName + "Title";
                                return scope[attrName] || scope.defaultTitle;
                            };

                            scope.title = lookupTitle(ngModelCtrl.$modelValue || processingIconStates.default);
                            scope.state = ngModelCtrl.$modelValue || processingIconStates.default;

                            ngModelCtrl.$validators = function(modelValue, viewValue) {

                                // verify its one of the allowed values.
                                var value = modelValue || viewValue;
                                return validStates.indexOf(value) !== -1;
                            };
                            ngModelCtrl.$render = function() {
                                var state = ngModelCtrl.$viewValue;
                                scope.state = state;
                                scope.title = lookupTitle(state);
                            };
                        };
                    }
                };
            }
        ]);
    }
);
