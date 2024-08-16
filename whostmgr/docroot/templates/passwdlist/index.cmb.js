/*
# templates/passwdlist/services/PasswordListService.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */
/* jshint -W089 */

define(
    'app/services/PasswordListService',[
        "angular",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, APIREQUEST) {
        "use strict";

        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.apicatcher", "cjt2.services.api"]); // Fall-back for unit testing
        }

        return app.factory("PasswordListService", ["APICatcher", "APIService", function(api, apiService) {

            var NO_MODULE = "";

            /**
             * Calls WHM API to request passsword change on the supplied username and password.
             *
             * @method requestPasswordChange
             * @param {String} user      The WHM username on which to update the password.
             * @param {String} password  The new password for the WHM user to update.
             * @param {Boolean} enableDigestAuth  Enable Digest Authentication for user.
             *
             * @return {Promise}         Object that return success or failure results.
             */
            function requestPasswordChange(user, password, enableDigestAuth, syncMySQLPassword) {

                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "passwd", {
                        "user": user,
                        "password": password,
                        "enabledigest": enableDigestAuth ? "1" : "0",
                        "db_pass_update": syncMySQLPassword ? "1" : "0"
                    }
                );

                return apiService.promise(apiCall);
            }

            /**
             * Check if a user has digest authentication enabled
             *
             * @method hasDigestAuth
             *
             * @param  {String} user username to lookup
             *
             * @return {Promise} returns the apiCall promise which then returns the boolean result of the call
             *
             */
            function hasDigestAuth(user) {
                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "has_digest_auth", {
                        user: user
                    }
                );

                return api.promise(apiCall).then(function(result) {
                    return result.data.digestauth && result.data.digestauth.toString() === "1";
                });
            }

            /**
             * Check if a user has a .my.cnf file
             *
             * @method hasMySQLCnf
             *
             * @param  {String} user username to lookup
             *
             * @return {Promise} returns the apiCall promise which then returns the boolean results of the call
             *
             */
            function hasMySQLCnf(user) {

                //
                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "has_mycnf_for_cpuser", {
                        user: user
                    }
                );

                return api.promise(apiCall).then(function(result) {
                    return result.data.has_mycnf_for_cpuser && result.data.has_mycnf_for_cpuser.toString() === "1";
                });
            }

            return {
                requestPasswordChange: requestPasswordChange,
                hasDigestAuth: hasDigestAuth,
                hasMySQLCnf: hasMySQLCnf
            };

        }]);
    }
);

/*
# whostmgr/docroot/templates/passwdlist/index.js     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, require:false, PAGE: false */
/* jshint -W100 */

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

        var DEFAULT_PASSWORD_STRENGTH = 10;


        return function() {

            angular.module("App", [
                "cjt2.whm",
                "cjt2.config.whm.configProvider",
                "ngAnimate",
                "ngSanitize",
                "angular-growl"
            ]);

            var app = require([
                "cjt/bootstrap",
                "cjt/directives/validateEqualsDirective",
                "cjt/directives/passwordFieldDirective",
                "cjt/directives/toggleLabelInfoDirective",
                "cjt/directives/actionButtonDirective",
                "cjt/directives/validationContainerDirective",
                "cjt/directives/validationItemDirective",
                "app/services/PasswordListService",
                "cjt/directives/whm/userDomainListDirective"
            ], function(bootstrap) {

                var app = angular.module("App");

                app.controller("PasswordListController", [
                    "$scope",
                    "PasswordListService",
                    "growl",
                    function($scope, $service, growl) {

                        // Bring in the globally set required password strength setting, or default to this app's internal password strength requirements.
                        var minimumPasswordStrength = angular.isDefined(PAGE.MINIMUM_PASSWORD_STRENGTH) ? parseInt(PAGE.MINIMUM_PASSWORD_STRENGTH, 10) : DEFAULT_PASSWORD_STRENGTH;
                        var currentDigestAuthCheck, currentHasMyCnfCheck;

                        var editLockedAccounts = {};
                        if (PAGE.childWorkloadAccounts) {
                            PAGE.childWorkloadAccounts.forEach(function(key) {
                                editLockedAccounts[key] = LOCALE.maketext("You must edit the password of this account on the parent node.");
                            });
                        }

                        $scope.editLockedAccounts = editLockedAccounts;

                        /**
                            * Calls $service on view button click to request passsword change on the user and password.
                            *
                            * @method submitChangePassword
                            *
                            */
                        function submitChangePassword() {
                            if (!$scope.selectedDomain || !$scope.selectedDomain.user) {
                                return false;
                            }

                            var syncMySQLPass = true;

                            if ($scope.hasMyCnf && !$scope.userConfig.syncMySQLPass) {
                                syncMySQLPass = false;
                            }

                            return $service.requestPasswordChange(
                                $scope.selectedDomain.user,
                                $scope.password,
                                $scope.userConfig.enableDigestAuth,
                                syncMySQLPass
                            ).then(function(result) {

                                // show success
                                growl.success(LOCALE.maketext("The system successfully updated the “[_1]” password. The following service passwords changed: [list_and,_2]", $scope.selectedDomain.user, result.data));
                                resetAllFields();
                            }, function(error) {

                                // show failure
                                growl.error(LOCALE.maketext("An error occurred while updating the password: [_1]", error.error));
                                resetAllFields();
                            });

                        }

                        /**
                            * Resets all input form fields and clears any validator messages after receiving API results.
                            *
                            * @method resetAllFields
                            *
                            */
                        function resetAllFields() {
                            $scope.password = $scope.confirmPassword = "";
                            if ($scope.changePasswordForm) {
                                $scope.changePasswordForm.$setPristine();
                            }
                        }

                        /**
                             * Function called on selection of the user
                             *
                             * @method userSelected
                             *
                             * @param  {String} user selected user
                             *
                             *
                             */
                        function userSelected(user) {
                            document.getElementById("changePasswordForm").elements.namedItem("password").focus();
                            _updateUserChecks(user);
                            return true;
                        }

                        function _updateUserChecks(user) {

                            $scope.userConfig = {};
                            $scope.userConfig.enableDigestAuth = false;
                            $scope.hasMyCnf = false;

                            if (currentDigestAuthCheck && currentDigestAuthCheck.abort) {
                                currentDigestAuthCheck.abort();
                                currentDigestAuthCheck = null;
                            }
                            currentDigestAuthCheck = $service.hasDigestAuth(user).then(function(result) {
                                $scope.userConfig.enableDigestAuth = result;
                            }).finally(function() {
                                currentDigestAuthCheck = null;
                            });

                            if (PAGE.role_MySQLClient) {
                                if (currentHasMyCnfCheck && currentHasMyCnfCheck.abort) {
                                    currentHasMyCnfCheck.abort();
                                    currentHasMyCnfCheck = null;
                                }
                                currentHasMyCnfCheck = $service.hasMySQLCnf(user).then(function(result) {
                                    $scope.hasMyCnf = result;
                                    $scope.userConfig.syncMySQLPass = !$scope.hasMyCnf;
                                }).finally(function() {
                                    currentHasMyCnfCheck = null;
                                });
                            } else {
                                $scope.userConfig.syncMySQLPass = false;
                            }
                        }

                        angular.extend($scope, {
                            domains: PAGE.domains,
                            password: "",
                            minimumPasswordStrength: minimumPasswordStrength,
                            selectedDomain: null,
                            resetAllFields: resetAllFields,
                            userSelected: userSelected,
                            submitChangePassword: submitChangePassword.bind($scope)
                        });

                    }
                ]);

                bootstrap("#passwdListWidget");

            });

            return app;
        };
    }
);

