/*
# cjt/directives/actionButtonDirective.js            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/test",
        "cjt/directives/spinnerDirective",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, TEST) {

        "use strict";

        // Retrieve the application object
        var module = angular.module("cjt2.directives.actionButton", [
            "cjt2.templates",
            "cjt2.directives.spinner"
        ]);

        /**
         * Directive that produces a button with an embedded spinner. The spinner starts and the button is
         * disabled when the button is clicked. Once the action is done processing, the button is enabled
         * and the spinner is stopped and hidden.
         *
         * @attribute {Function|Promise} cp-action The function call to make after starting the spinner. If a Promise, then handled async, if a function then handled sync.
         * @attribute {String} [spinnerId] Optional id for the spinner. You only need to set this is you want to
         * have control of the spinner independently of the built in behavior.
         *
         * @example
         *
         * Basic usage:
         * <button cp-action="takeAction">
         *
         * Providing a custom spinner id:
         * <button spinner-id="ActionButton" action="takeAction">
         *
         * Synchronous Action:
         *
         * For a synchronous action, the action should be a function that performs some long running
         * task. Once the function returns, the spinner will stop. Note that we pass the function in the
         * markup here
         *
         * <button cp-action="takeAction">
         *
         * $scope.takeAction = function() {
         *     // do something long sync process
         * }
         *
         * Synchronous Action with Parameter:
         *
         * For a synchronous action that needs to pass a parameter, the action should be a function that returns a function that
         * performs some long running task. Once the function returns, the spinner will stop. Note that we pass the function in the
         * markup here
         *
         * <button cp-action="takeAction($index)">
         *
         * $scope.takeAction = function($index) {
         *     return function() {
         *         // do something long sync process
         *         // use the $index somehow
         *     }
         * }
         *
         * Asynchronous Action:
         *
         * For a asynchronous action, the action function should be a function that starts an asynchronous
         * task and returns a promise. Once the promise resolves or is rejected, the spinner will stop. Note
         * that we call the function in the markup here.
         *
         * <button cp-action="takeAction()">
         *
         * $scope.takeAction = function() {
         *     var deferred = $q.defer();
         *     $timeout(function() {
         *         deferred.resolve();
         *     }, 1000);
         *     return deferred.promise;
         * }
         *
         * Classes:
         *
         * Because this directive uses replacement, using class attributes on the original element don't always get passed to the
         * resulting button the way you'd expect. For this reason, you should use the button-class and button-ng-class attributes
         * to style the final button. The "btn" class is always included by default. If you don't provide any button-class or
         * button-ng-class attributes then the default classes of "btn btn-primary" will be applied. The button-ng-classes
         * attribute will be evaluated against the parent scope so it's pretty flexible.
         *
         * "btn btn-primary"
         * <button cp-action="doSomething()">
         *
         * "btn btn-warning"
         * <button cp-action="doSomething()" button-class="btn-warning">
         *
         * "btn btn-warning" if isWarning
         * "btn btn-danger"  if isError
         * <button cp-action="doSomething()" button-ng-class="{ 'btn-warning' : isWarning, 'btn-danger' : isError }">
         *
         * "btn" and whatever classes are provided by getButtonClasses on the parent scope
         * <button cp-action="doSomething()" button-ng-class="getButtonClasses()">
         */
        module.directive("cpAction", ["spinnerAPI", "$log", function(spinnerAPI, $log) {
            var ctr = 0;
            var DEFAULT_AUTO_DISABLE = true;
            var DEFAULT_CONTROL_NAME = "actionButton";
            var DEFAULT_BUTTON_CLASS = "btn-primary";
            var RELATIVE_PATH = "libraries/cjt2/directives/actionButton.phtml";

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                restrict: "A",
                transclude: true,
                replace: true,
                priority: 10,
                scope: {

                    // spinnerId: "@spinnerId", // REMOVED: Due to an issue with auto one way binding, seems that if you want defaults to work
                    // with nested controls, you must set the scope in the pre() method, but if you use the
                    // isolated scope @, you can't set the default right. Its missing during the critical
                    // phase when the nested controls need it.
                    buttonClass: "@buttonClass",
                    buttonNgClass: "&",
                    action: "&cpAction",
                    autoDisable: "@?autoDisable",
                    actionActive: "@?",
                },
                /* eslint-disable no-unused-vars */
                compile: function(element, attrs) {
                /* eslint-enable no-unused-vars */
                    return {
                        /* eslint-disable no-unused-vars */
                        pre: function(scope, element, attrs) {

                            if (attrs.ngBind) {
                                $log.error("ngBind is not supported on this directive. It causes the spinner to stop working");
                            }

                            // Set the defaults
                            var id = angular.isDefined(attrs.id) && attrs.id !== "" ? attrs.id : DEFAULT_CONTROL_NAME + ctr++;
                            attrs.spinnerId = angular.isDefined(attrs.spinnerId) && attrs.spinnerId !== "" ? attrs.spinnerId : id + "_Spinner";
                            if (!angular.isDefined(attrs.buttonNgClass)) {
                                attrs.buttonClass = angular.isDefined(attrs.buttonClass) && attrs.buttonClass !== "" ? attrs.buttonClass : DEFAULT_BUTTON_CLASS;
                            }

                            // remember, autoDisable is a string because of the "@" isolate scope property
                            // we need to convert it to a proper boolean
                            var tmpAutoDisable = attrs.autoDisable;
                            attrs.autoDisable = DEFAULT_AUTO_DISABLE;
                            if (angular.isDefined(tmpAutoDisable)) {
                                if (tmpAutoDisable === "false") {
                                    attrs.autoDisable = false;
                                } else if (tmpAutoDisable === "true") {
                                    attrs.autoDisable = true;
                                }
                            }

                            // Capture the id so the template can use it.
                            scope.spinnerId = attrs.spinnerId;
                            scope.autoDisable = attrs.autoDisable;
                        },
                        /* eslint-enable no-unused-vars */
                        post: function(scope, element, attrs) {
                            scope.running = false;

                            /**
                             * Stop the spinner and enable the button again.
                             * @method finish
                             * @private
                             */
                            var finish = function() {
                                if (scope.autoDisable) {
                                    element.prop("disabled", false);
                                }
                                scope.running = false;
                                spinnerAPI.stop(scope.spinnerId, false);
                            };

                            /**
                             * Starts the action specified by the method property
                             * @protected
                             */
                            scope.start = function() {
                                _start();
                                var action = scope.action();
                                if (TEST.isQPromise(action)) {

                                    // Async
                                    action.finally(finish);
                                } else {

                                    // Sync
                                    finish();
                                }
                            };

                            function _start() {
                                if (scope.autoDisable) {
                                    element.prop("disabled", true);
                                }
                                spinnerAPI.start(scope.spinnerId);
                                scope.running = true;
                            }

                            /**
                             * Combines the button-ng-class values with a default ng-class object that handles the
                             * loading/process font icon. The ng-class directive will evaluate each item in the array
                             * separately, so mixed formats (string, object, or array) are fine.
                             *
                             * @method ngClass
                             * @return {Array}   An array that will be consumed by the ng-class directive.
                             */
                            scope.ngClass = function() {
                                var finalNgClass = [{
                                    "button-loading": scope.running
                                }];

                                var buttonNgClass = scope.buttonNgClass();
                                if (buttonNgClass) {
                                    if (angular.isArray(buttonNgClass)) {
                                        finalNgClass = finalNgClass.concat(buttonNgClass);
                                    } else {
                                        finalNgClass.push(buttonNgClass);
                                    }
                                }

                                return finalNgClass;
                            };

                            /**
                             * Allows the directive to change states based on a boolean, useful if your page is perfoming an action prior to, or after the button click.
                             */
                            attrs.$observe("actionActive", function(newVal) {
                                scope.actionActive = attrs.actionActive = (newVal === "true");
                                if (attrs.actionActive) {
                                    _start();
                                } else {
                                    finish();
                                }
                            });
                        }
                    };
                }
            };
        }]);
    }
);
