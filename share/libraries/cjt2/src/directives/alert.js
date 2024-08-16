/*
# cjt/directives/alert.js                         Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
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

        var module = angular.module("cjt2.directives.alert", [
            "cjt2.templates"
        ]);

        /**
         * Directive that shows an alert.
         * @example
         *
         * Example of a collection of alerts:
         *
         * <cp:alert ng-repeat="alert in alerts"
         *        ng-model="alert"
         *        on-close="myCloseFn($index)">
         * </cp:alert>
         *
         * Where alert-data is an object in the following the form:
         *
         * {
         *     message:       {String}  The alert message text.
         *     type:      {String}  The type of alert.
         *     closeable: {Boolean} Is the user able to dismiss the alert?
         * }
         *
         * And alerts is an array of alert objects. One could add to the
         * list of alerts by simply pushing a new one to the array:
         *
         * $scope.alerts.push({
         *     message  : message,
         *     type : type || "info"
         * });
         *
         * Example of an alert with transcluded text
         *
         * <cp:alert type="danger">
         *     Something bad happened!!!
         * </cp:alert>
         *
         * Example of an alert with transcluded html with filter
         *
         * <cp:alert type="danger" ng-init="message='what\nare\nyou looking at.'">
         *     <span ng-bind-html="message | break"></span>
         * </cp:alert>
         *
         * Example of alert with auto close of 10 seconds.
         *
         * <cp:alert type="info" auto-close="10000">
         *     Just letting you know something, but it will go away in 10 seconds.
         * </cp:alert>
         *
         * Example of alert with more link.
         *
         * scope.showMore = false;
         * scope.toggleMore = function(show, id) {
         *     scope.showMore = show;
         * }
         *
         * <cp:alert type="error" on-toggle-more="toggleMore(show, id)" more-label="More">
         *     Just letting you know an error at the high level.
         *     <div class="well ng-hide" ng-show="showMore">
         *         And here are some more details that you don't need unless you are an expert.
         *     </div>
         * </cp:alert>
         *
         */
        module.directive("cpAlert", ["$timeout", "$compile",
            function($timeout, $compile) {
                var _counter = 0;
                var ID_DEFAULT_PREFIX = "alert";
                var RELATIVE_PATH = "libraries/cjt2/directives/alert.phtml";

                var LABELS = [{
                    name: "errorLabel",
                    defaultText: LOCALE.maketext("Error:"),
                }, {
                    name: "warnLabel",
                    defaultText: LOCALE.maketext("Warning:")
                }, {
                    name: "infoLabel",
                    defaultText: LOCALE.maketext("Information:")
                }, {
                    name: "successLabel",
                    defaultText: LOCALE.maketext("Success:")
                }, {
                    name: "moreLabel",
                    defaultText: LOCALE.maketext("What went wrong?")
                }];

                /**
                 * Initialize the model state with defaults and other business logic. Model can be
                 * setup via an optional ng-model or via inline attributes on the directive.
                 *
                 * @private
                 * @method initializeModel
                 * @param  {Boolean} hasModel true indicates that a model is used, false indicates to use attribute rules.
                 * @param  {Array}  attrs
                 * @param  {String|Object|Undefined}  modelValue
                 * @return {Object}             Fully filled out model for the alert.
                 */
                var initializeModel = function(hasModel, attrs, modelValue) {
                    var data = {};

                    if (hasModel) {
                        if (angular.isString(modelValue)) {
                            data.message = modelValue;
                        } else if (angular.isObject(modelValue)) {
                            angular.copy(modelValue, data);
                        } else {
                            throw new TypeError("ngModel must be a string or object.");
                        }
                    }

                    if (!angular.isDefined(data.type)) {
                        if (angular.isDefined(attrs.type) && attrs.type) {
                            data.type = attrs.type;
                        } else {
                            data.type = "warning";
                        }
                    }

                    if (angular.isDefined(data.closable)) {

                        // We don't want users to be able to close errors, only the application
                        //  code can do this.  Otherwise, accept the users choices.
                        data.closable = ((data.type === "danger") ? false : data.closable);
                    } else if (angular.isDefined(attrs.closable)) {
                        data.closable = ((data.type === "danger") ? false : true);
                    } else {
                        data.closable = false;
                    }

                    if (CJT.isE2E()) {
                        data.autoClose = false;
                    } else if (angular.isDefined(data.autoClose)) {

                        // We don't want errors to auto close either.
                        data.autoClose = ((data.type === "danger") ? false : data.autoClose);
                    } else if (angular.isDefined(attrs.autoClose)) {
                        data.autoClose = ((data.type === "danger") ? false : data.autoClose);
                    } else {
                        data.autoClose = false;
                    }

                    if (!angular.isDefined(data.id)) {
                        if (!angular.isDefined(attrs.id)) {

                            // Guarantee we have some kind of id.
                            data.id = ID_DEFAULT_PREFIX + _counter++;
                        } else {

                            // Guarantee we have some kind of id.
                            data.id = attrs.id;
                        }
                    }

                    if (hasModel && !angular.isDefined(data.message) && !data.message) {
                        throw new Error("No message provided in the model's message property.");
                    } // Otherwise, its just transcluded.

                    return data;
                };

                /**
                 * Render the body using the transclusion. Only called if using transclusion!!!
                 *
                 * @method renderBody
                 * @param  {Object} scope      directive scope
                 * @param  {Object} element    directive element
                 * @param  {Function} transclude directive transclude function
                 */
                var renderBody = function(scope, element, transclude) {

                    // Process the transclude
                    var type = scope.alert.type;
                    var typeBlock = element[0].querySelector(".alert-" + type);
                    var messageSpan = typeBlock.querySelector(".alert-body");

                    transclude(function(clone) {

                        // append the transcluded element.
                        angular.element(messageSpan).append(clone);
                    });
                };


                return {
                    restrict: "EA",
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    transclude: true,
                    replace: true,
                    require: "?ngModel",
                    scope: {
                        close: "&onClose",
                        toggleMore: "&onToggleMore",
                        autoClose: "=",
                        errorLabel: "@",
                        warnLabel: "@",
                        infoLabel: "@",
                        successLabel: "@",
                        moreLabel: "@"
                    },
                    compile: function(element, attrs) {

                        // Initialize any labels not provided
                        LABELS.forEach(function(label) {
                            if (!angular.isDefined(attrs[label.name])) {
                                attrs[label.name] = label.defaultText;
                            }
                        });

                        return function(scope, element, attrs, ngModelCtrl, transclude) {

                            // Prepare the model by adding any missing parts to their appropriate defaults.
                            if (ngModelCtrl) {
                                ngModelCtrl.$formatters.push(function(modelValue) {
                                    return initializeModel(true, attrs, modelValue);
                                });

                                ngModelCtrl.$render = function() {
                                    scope.alert = ngModelCtrl.$viewValue;
                                    $timeout(function() {
                                        scope.$emit("addAlertCalled");
                                    }, 0);
                                };
                            } else {
                                scope.alert = initializeModel(false, attrs);
                                renderBody(scope, element, transclude);
                            }

                            /**
                             * Set all of the label attributes to the model's label value, if it exists.
                             */
                            scope.$watch("alert.label", function(newVal) {
                                if ( angular.isDefined(newVal) ) {
                                    LABELS.forEach(function(label) {
                                        attrs.$set(label.name, newVal);
                                    });
                                }
                            });

                            /**
                             * Helper method to handle manual closing of an alert.
                             */
                            scope.runClose = function() {
                                if (scope.timer) {
                                    var timer = scope.timer;
                                    scope.timer = null;
                                    delete scope.timer;
                                    $timeout.cancel(timer);
                                }

                                /* for alertList (or anything else that might want to use it) */
                                scope.$emit("closeAlertCalled", {
                                    id: scope.alert.id
                                });
                                scope.close();
                            };

                            // Check if autoClose is set and set the close timer if it is
                            var msecs = scope.autoClose ? parseInt(scope.autoClose, 10) : null;
                            if (msecs && !isNaN(msecs)) {
                                scope.timer = $timeout(function() {
                                    scope.runClose();
                                }, msecs);
                            }

                            // Add the toggle more support. What the toggle more button
                            // does is defined by the user of the directive, probably
                            // in the body of the alert, but not necessarily. Its designed
                            // to provide a way to embed technical details into the alert
                            // but not show them by default.
                            scope.hasToggleHandler = angular.isDefined(attrs.onToggleMore);
                            scope.showMore = false;
                            scope.runToggleMore = function() {
                                scope.showMore = !scope.showMore;
                                var e = {
                                    id: scope.alert.id,
                                    show: scope.showMore
                                };
                                scope.$emit("toggleMoreAlertCalled", e);
                                scope.toggleMore(e);
                            };

                        };
                    }
                };
            }
        ]);
    }
);
