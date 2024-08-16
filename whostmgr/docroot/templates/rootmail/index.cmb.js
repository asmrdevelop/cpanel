/*
# rootmail/services/mailPrefService.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/mailPrefService',[

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }


        app.factory("mailPrefService", ["$q", "APIService",
            function($q, APIService) {

                // private  functions used within the service
                // service workhorses

                // Set up the service's constructor and parent
                var BaseService = function() {};
                BaseService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(BaseService.prototype, {

                    /**
                     * get forward location for provided user
                     *
                     * @method get_user_email_forward_destination
                     * @param  {String} user User name for which to get the user forward address.
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    get_user_email_forward_destination: function(user) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "get_user_email_forward_destination");
                        apiCall.addArgument("user", user);

                        var deferred = this.deferred(apiCall);

                        // pass the promise back to the controller
                        return deferred.promise;
                    },

                    /**
                     * set forward location for provided user
                     *
                     * @method set_user_email_forward_destination
                     * @param  {String} user User name for which to get the user forward address.
                     * @param  {String} forward_to Email address or username to forward to.
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    set_user_email_forward_destination: function(user, forward_to) {

                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "set_user_email_forward_destination");
                        apiCall.addArgument("user", user);
                        apiCall.addArgument("forward_to", forward_to);

                        var deferred = this.deferred(apiCall);

                        // pass the promise back to the controller
                        return deferred.promise;
                    },

                });

                return new BaseService();
            }
        ]);
    }
);

/*
# templates/rootmail/index.js                          Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */
/* jshint -W100 */

define(
    'app/index',[
        "angular",
        "cjt/util/locale",
        "lodash",
        "uiBootstrap",
        "cjt/core",
        "cjt/modules",
        "cjt/directives/actionButtonDirective"
    ],
    function(angular, LOCALE, _) {
        "use strict";

        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require([
                "cjt/bootstrap",

                // Application Modules
                "ngSanitize",
                "app/services/mailPrefService"
            ], function(BOOTSTRAP) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.controller("MainController", ["$scope", "mailPrefService", "spinnerAPI", "PAGE",
                    function($scope, mailPrefService, spinnerAPI, PAGE) {

                        $scope.users = [];

                        function _update_user(user, forward) {
                            angular.forEach($scope.users, function(userObj) {
                                if (userObj.user === user) {
                                    var emails = Array.isArray(forward) ? forward : forward.split(/\s*,\s*/);
                                    userObj.forward = userObj.newforward = emails;
                                }
                            });
                        }

                        $scope.get_user_forward = function(user) {
                            spinnerAPI.start(user + "-spinner");
                            return mailPrefService.get_user_email_forward_destination(user)
                                .then(function(results) {
                                    spinnerAPI.stop(user + "-spinner");
                                    _update_user(user, results.data.forward_to);
                                });
                        };

                        $scope.set_user_forward = function(user, forward_to) {
                            spinnerAPI.start(user + "-spinner");
                            return mailPrefService.set_user_email_forward_destination(user, forward_to)
                                .then(function() {
                                    spinnerAPI.stop(user + "-spinner");
                                    _update_user(user, forward_to);
                                });
                        };
                        $scope.get_panel_title = function(user) {
                            if (user.forward && user.forward.length && user.forward[0].length) {
                                return LOCALE.maketext("The system currently forwards mail for “[output,strong,_1]” to “[list_and,_2]”.", user.user, _.escape(user.forward));
                            }

                            return LOCALE.maketext("The system does not currently forward mail for “[output,strong,_1]”.", user.user);
                        };

                        $scope.validate_user = function(user) {
                            if (!user.newforward || user.newforward === "") {

                                // Empty strings turn forwarding off
                                return true;
                            }
                            user.errors = [];

                            var forwards = Array.isArray(user.newforward) ? forwards : user.newforward.split(/\s*,\s*/);
                            angular.forEach(forwards, function(forward) {
                                if (/@/.test(forward)) {

                                    // If the input contains a @ validate it as a proper email address
                                    if (!CPANEL.validate.email(forward, "rfc")) {
                                        user.errors.push(LOCALE.maketext("The email address “[_1]” is not valid.", forward));
                                    }
                                } else {

                                    // Otherwise assume its going to a local box
                                    if (!PAGE.local_users[forward]) {
                                        user.errors.push(LOCALE.maketext("The user “[_1]” does not exist on the system.", forward));
                                    }
                                }
                            });

                            return user.errors.length ? false : true;
                        };

                        $scope.get_submit_label = function(user) {
                            if (user.newforward !== user.forward && user.newforward === "") {
                                return LOCALE.maketext("Disable");
                            }

                            return LOCALE.maketext("Update");
                        };

                        $scope.get_forward_mail_label = function(user) {
                            return LOCALE.maketext("Forward mail for “[_1]” to:", user.user);
                        };

                        angular.forEach(PAGE.users, function(forward, user) {
                            var userObj = {
                                user: user,
                                forward: forward,
                                newforward: forward
                            };

                            $scope.validate_user(userObj);
                            $scope.users.push(userObj);
                        });

                    }
                ]);

                BOOTSTRAP(document);

            });

            return app;
        };
    }
);


var init = function() {
    var validation = [];

    // Get all the input fields and attach mail validation to them
    var els = YAHOO.util.Dom.getElementsByClassName("mail-field");

    for (var i = 0; i < els.length; i++) {
        validation[i] = new CPANEL.validate.validator("Mail Preferences");
        validation[i].add(els[i], "external_verify_content", LOCALE.maketext("Must be a valid email address or account name"));
        validation[i].attach();
    }

    // Get all the submit buttons and attach validation
    els = YAHOO.util.Dom.getElementsByClassName("btn-primary");
    for (i = 0; i < els.length; i++) {
        CPANEL.validate.attach_to_form(els[i], validation[i]);
    }


};

YAHOO.util.Event.onDOMReady(init);

