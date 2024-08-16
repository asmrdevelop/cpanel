/*
 * changePasswordService.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
define(
    'app/services/changePasswordService',[
        "angular",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST) {

        // Get the current application
        var app = angular.module("whm.changeRootPassword");

        app.factory("changePasswordService", ["$q", "APIService", function($q, APIService) {
            var ChangePasswordService = function() {};
            ChangePasswordService.prototype = new APIService();

            angular.extend(ChangePasswordService.prototype, {

                /**
                 * Calls WHM API to request passsword change on the supplied username and password.
                 *
                 * @method requestPasswordChange
                 * @param {String} user      The WHM username on which to update the password.
                 * @param {String} password  The new password for the WHM user to update.
                 *
                 * @return {Promise}         Object that return success or failure results.
                 */
                requestPasswordChange: function(user, password) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "passwd");
                    apiCall.addArgument("user", user);
                    apiCall.addArgument("password", password);

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                }
            });
            return new ChangePasswordService();
        }]);
    }
);

/*
 * index.js                                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global require: false, define: false, PAGE: false */

define(
    'app/index',[
        "angular",
        "cjt/util/locale",
        "cjt/modules",
        "ngAnimate",
        "ngSanitize"
    ],
    function(angular, LOCALE) {
        "use strict";

        return function() {
            angular.module("whm.changeRootPassword", [
                "cjt2.whm",
                "cjt2.config.whm.configProvider",
                "ngAnimate",
                "ngSanitize",
                "angular-growl"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/directives/validateEqualsDirective",
                    "cjt/directives/passwordFieldDirective",
                    "cjt/directives/toggleLabelInfoDirective",
                    "cjt/directives/actionButtonDirective",
                    "cjt/directives/validationContainerDirective",
                    "cjt/directives/validationItemDirective",
                    "app/services/changePasswordService"
                ], function(BOOTSTRAP) {

                    var DEFAULT_PASSWORD_STRENGTH = 10;
                    var app = angular.module("whm.changeRootPassword");

                    app.controller("changeRootPasswordController", [
                        "$scope",
                        "changePasswordService",
                        "growl",
                        function(
                            $scope,
                            changePasswordService,
                            growl
                        ) {

                            // To prevent browsers from auto filling the password. autocomplete="off" not working on all browsers
                            // https://developer.mozilla.org/en-US/docs/Web/Security/Securing_your_site/Turning_off_form_autocompletion
                            $scope.password = "";

                            // Bring in the globally set required password strength setting, or default to this app's internal password strength requirements.
                            $scope.minimumPasswordStrength = angular.isDefined(PAGE.MINIMUM_PASSWORD_STRENGTH) ? parseInt(PAGE.MINIMUM_PASSWORD_STRENGTH, 10) : DEFAULT_PASSWORD_STRENGTH;

                            /**
                            * Calls changePasswordService on view button click to request passsword change on the preset "root" user and password.
                            *
                            * @method submitChangeRootPassword
                            *
                            */
                            $scope.submitChangeRootPassword = function() {
                                return changePasswordService.requestPasswordChange("root", $scope.password)
                                    .then(function(result) {

                                    // show success
                                        growl.success(LOCALE.maketext("The system successfully updated the [asis,root] password. The following service passwords changed: [list_and,_1]", result.data));
                                        resetAllFields();
                                    }, function(error) {

                                    // show failure
                                        growl.error(error);
                                        resetAllFields();
                                    });

                            };

                            /**
                            * Resets all input form fields and clears any validator messages after receiving API results.
                            *
                            * @method resetAllFields
                            *
                            */
                            function resetAllFields() {
                                $scope.password = $scope.confirmPassword = "";
                                if ($scope.changeRootPasswordForm) {
                                    $scope.changeRootPasswordForm.$setPristine();
                                }
                            }
                        }
                    ]);

                    BOOTSTRAP(document, "whm.changeRootPassword");
                });
            return app;
        };
    }
);

