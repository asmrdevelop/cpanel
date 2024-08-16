/*
# cpanel - base/webmail/jupiter/account_preferences/services/accountPrefs.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/services/accountPrefs',[
        "angular",
        "lodash",
        "cjt/io/uapi-request",
        "cjt/modules",
        "cjt/io/api",
        "cjt/io/uapi",
        "cjt/services/APICatcher",
    ],
    function(angular, _, APIRequest) {

        "use strict";

        var MODULE_NAMESPACE = "webmail.accountPrefs.services.accountPrefs";
        var SERVICE_NAME = "AccountPrefsService";
        var MODULE_REQUIREMENTS = [ "cjt2.services.apicatcher" ];
        var SERVICE_INJECTABLES = ["APICatcher"];

        /**
         *
         * Service Factory to generate the Account Preferences service
         *
         * @module AccountPrefsService
         * @memberof webmail.accountPrefs
         *
         * @param {Object} APICatcher base service
         * @returns {Service} instance of the Domains service
         */
        var SERVICE_FACTORY = function(APICatcher) {

            var Service = function() {};

            Service.prototype = Object.create(APICatcher);

            _.assign(Service.prototype, {

                /**
                 * Wrapper for building an apiCall
                 *
                 * @private
                 *
                 * @param {String} module module name to call
                 * @param {String} func api function name to call
                 * @param {Object} args key value pairs to pass to the api
                 * @returns {UAPIRequest} returns the api call
                 *
                 * @example _apiCall( "Email", "get_mailbox_autocreate", { email:"foo@bar.com" } )
                 */
                _apiCall: function _createApiCall(module, func, args) {
                    var apiCall = new APIRequest.Class();
                    apiCall.initialize(module, func, args);
                    return apiCall;
                },

                /**
                 * Process the return value of the isMailboxAutoCreateEnabled call
                 *
                 * @param {Object} response object containing the data value
                 * @returns {Boolean} boolean value state of get_mailbox_autocreate
                 *
                 * @example _processMailboxAutoCreateResponse( { data:1 } )
                 */
                _processMailboxAutoCreateResponse: function _processPAResponse(response) {
                    return response && response.data && response.data.toString() === "1";
                },

                /**
                 * Retrieve current state of an email address's ability to auto create folders
                 *
                 * @param {String} email email address to check
                 * @returns {Promise<Boolean>} parsed value of the get_mailbox_autocreate call
                 *
                 * @example $service.isMailboxAutoCreateEnabled("foo@bar.com");
                 */
                isMailboxAutoCreateEnabled: function isMailboxAutoCreateEnabled(email) {
                    var apiCall = this._apiCall("Email", "get_mailbox_autocreate", { email: email });
                    return this._promise(apiCall).then(this._processMailboxAutoCreateResponse);
                },

                /**
                 * Enable Mailbox Auto Creation for an email address
                 *
                 * @param {String} email email address on which to enable auto creation
                 * @returns {Promise}
                 *
                 * @example $service.enableMailboxAutoCreate("foo@bar.com");
                 */
                enableMailboxAutoCreate: function enableMailboxAutoCreate(email) {
                    var apiCall = this._apiCall("Email", "enable_mailbox_autocreate", { email: email });
                    return this._promise(apiCall);
                },

                /**
                 * Disable Mailbox Auto Creation for an email address
                 *
                 * @param {String} email email address on which to enable auto creation
                 * @returns {Promise}
                 *
                 * @example $service.disableMailboxAutoCreate("foo@bar.com");
                 */
                disableMailboxAutoCreate: function disableMailboxAutoCreate(email) {
                    var apiCall = this._apiCall("Email", "disable_mailbox_autocreate", { email: email });
                    return this._promise(apiCall);
                },

                /**
                 * Wrapper for .promise method from APICatcher
                 *
                 * @param {Object} apiCall api call to pass to .promise
                 * @returns {Promise}
                 *
                 * @example $service._promise( $service._apiCall( "Email", "get_mailbox_autocreate", { email:"foo@bar.com" } ) );
                 */
                _promise: function _promise() {

                    // Because nested inheritence is annoying
                    return APICatcher.promise.apply(this, arguments);
                },
            });

            return new Service();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE,
        };
    }
);

/*
# cpanel - base/webmail/jupiter/account_preferences/views/main.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/main',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/accountPrefs",
        "cjt/modules",
        "cjt/services/alertService",
        "cjt/directives/toggleSwitchDirective",
        "cjt/directives/toggleLabelInfoDirective",
    ],
    function(angular, _, LOCALE, AccountPrefsService) {

        "use strict";

        var initialLoadVariable = "MAILBOX_AUTOCREATION_ENABLED";
        var MODULE_NAMESPACE = "webmail.accountPrefs.views.main";
        var TEMPLATE_URL = "views/main.ptt";
        var MODULE_DEPENDANCIES = [];

        var CONTROLLER_INJECTABLES = ["$scope", AccountPrefsService.serviceName, "alertService", initialLoadVariable, "RESOURCE_TEMPLATE", "EMAIL_ADDRESS", "DISPLAY_EMAIL_ADDRESS"];
        var CONTROLLER_NAME = "MainController";
        var CONTROLLER = function AccountPreferencesMainController($scope, $service, $alertService, mailboxAutoCreationEnabled, RESOURCE_TEMPLATE, email, displayEmailAddress) {
            $scope.email = email;
            $scope.displayEmailAddress = _.escape(displayEmailAddress);
            $scope.examplePlusAddress = $scope.displayEmailAddress.split("@").join("+plusaddress@");

            $scope.resourcesPanelTemplate = RESOURCE_TEMPLATE;
            $scope.mailboxAutoCreationEnabled = mailboxAutoCreationEnabled;

            /**
             * Enable Auto Folder Creation (Plus Addressing)
             *
             * @returns {Promise} update service promise
             */
            $scope.enableMailboxAutoCreate = function enableMailboxAutoCreate() {
                var onSuccess = $alertService.success.bind($alertService, LOCALE.maketext("You enabled automatic folder creation for “[_1]”.", $scope.displayEmailAddress));
                var onError = $alertService.add.bind($alertService, {
                    type: "danger",
                    message: LOCALE.maketext("The system could not enable automatic folder creation for “[_1]”.", $scope.displayEmailAddress),
                });
                return $service.enableMailboxAutoCreate($scope.email).then(onSuccess, onError);
            };

            /**
             * Disable Auto Folder Creation (Plus Addressing)
             *
             * @returns {Promise} update service promise
             */
            $scope.disableMailboxAutoCreate = function disableMailboxAutoCreate() {
                var onSuccess = $alertService.success.bind($alertService, LOCALE.maketext("You disabled automatic folder creation for “[_1]”.", $scope.displayEmailAddress));
                var onError = $alertService.add.bind($alertService, {
                    type: "danger",
                    message: LOCALE.maketext("The system could not disable automatic folder creation for “[_1]”.", $scope.displayEmailAddress),
                });
                return $service.disableMailboxAutoCreate($scope.email).then(onSuccess, onError);
            };

            /**
             * Toggle Whether Auto Folder Creation (Plus Addressing) is enabled
             *
             * @returns {Promise} update service promise
             */
            $scope.toggleAutoFolderCreation = function toggleAutoFolderCreation() {
                $scope.mailboxAutoCreationEnabled = !$scope.mailboxAutoCreationEnabled;
                return $scope.mailboxAutoCreationEnabled ? $scope.enableMailboxAutoCreate() : $scope.disableMailboxAutoCreate();
            };

        };

        var app = angular.module(MODULE_NAMESPACE, MODULE_DEPENDANCIES);
        app.controller(CONTROLLER_NAME, CONTROLLER_INJECTABLES.concat(CONTROLLER));

        var resolver = {};
        resolver[initialLoadVariable] = [
            AccountPrefsService.serviceName,
            "EMAIL_ADDRESS",
            function($service, EMAIL_ADDRESS) {
                return $service.isMailboxAutoCreateEnabled(EMAIL_ADDRESS);
            },
        ];

        return {
            "controller": CONTROLLER_NAME,
            "class": CONTROLLER,
            "template": TEMPLATE_URL,
            "namespace": MODULE_NAMESPACE,
            "resolver": resolver,
        };
    }
);

/*
# cpanel - base/webmail/jupiter/account_preferences/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/index',[
        "angular",
        "app/services/accountPrefs",
        "app/views/main",
        "cjt/modules",
        "cjt/directives/alertList",
        "cjt/services/APICatcher",
        "ngRoute",
        "uiBootstrap",
    ],
    function(angular, AccountPrefsService, MainView) {

        "use strict";

        var MODULE_NAME = "webmail.accountPrefs";

        return function() {

            // First create the application
            var appModule = angular.module(MODULE_NAME, [
                "ngRoute",
                "ui.bootstrap",
                "cjt2.webmail",
                AccountPrefsService.namespace,
                MainView.namespace,
            ]);

            appModule.value("EMAIL_ADDRESS", PAGE.emailAddress);
            appModule.value("DISPLAY_EMAIL_ADDRESS", PAGE.displayEmailAddress);
            appModule.value("RESOURCE_TEMPLATE", "views/_resources.ptt");

            // Then load the application dependencies
            var app = require(["cjt/bootstrap"], function(BOOTSTRAP) {

                appModule.config([
                    "$routeProvider",
                    function($routeProvider) {

                        $routeProvider.when("/", {
                            controller: MainView.controller,
                            templateUrl: MainView.template,
                            resolve: MainView.resolver,
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/",
                        });
                    },
                ]);

                BOOTSTRAP("#mainContent", MODULE_NAME);

            });

            return app;
        };
    }
);

