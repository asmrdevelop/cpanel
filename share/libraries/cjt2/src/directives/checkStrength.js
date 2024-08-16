/*
# cjt/directives/checkStrength.js                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// ------------------------------------------------------------
// Developer notes:
// ------------------------------------------------------------
// The concept for this construct was derived from:
// http://blog.brunoscopelliti.com/angularjs-directive-to-test-the-strength-of-a-password
// Used with permission.
// ------------------------------------------------------------

define(
    [
        "angular",
        "ngSanitize",
        "uiBootstrap",
        "cjt/services/passwordStrengthService"
    ],
    function(angular) {

        var module = angular.module("cjt2.directives.checkPasswordStrength", [
            "ui.bootstrap",
            "ngSanitize",
            "cjt2.services.passwordStrength"
        ]);

        /**
         * Directive that triggers a back-end password strength check on the selected field.
         * @example
         */
        module.directive("checkPasswordStrength", ["passwordStrength", function(passwordStrength) {
            return {
                require: "ngModel",
                priority: 1000,
                restrict: "EACM",
                replace: false,
                link: function(scope, el, attrs, ngModel) {

                    ngModel.$asyncValidators.passwordStrength = function(modelVal, viewVal) {
                        return _checkStrength(modelVal || viewVal);
                    };

                    /**
                     * asyncValidators don't run at all if the synchronous validators don't pass first,
                     * which means there is no passwordStrength event broadcast from the service if a
                     * password becomes invalid after being valid. That could cause models that rely on
                     * that event to go stale so we trigger the check here if we detect that the input
                     * is invalid.
                     */
                    scope.$watch(function() {

                        /**
                         * if the minlength validator has an error, then
                         * we should remove any displayed strength messages as they will be stale.
                         */
                        if (ngModel.$error.minlength) {
                            _checkStrength();
                        }
                        return ngModel.$invalid;
                    }, function() {
                        if (ngModel.$invalid && !ngModel.$error.minimumPasswordStrength) {
                            _checkStrength();
                        }
                    });

                    /**
                     * Dispatches the password strength check request through the service.
                     *
                     * @param  {String} password   The password to check.
                     * @return {Promise}           If resolved, the strength check succeeded. If rejected, it did not.
                     *                             This directive does not actually check the strength against the
                     *                             minimum required strength at this time.
                     */
                    function _checkStrength(password) {
                        var id = attrs.id || ngModel.$name;
                        var promise = passwordStrength.checkPasswordStrength(id, password);
                        return promise;
                    }

                }
            };
        }]);
    }
);
