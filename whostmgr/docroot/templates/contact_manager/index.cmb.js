/*
# templates/contact_manager/filters/notificationFilter.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/notificationFilter',[
        "angular"
    ],
    function(angular) {

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Filter for display_name or system_name of a given notification.
         * @param  {onject} item
         * @return {array}
         */
        app.filter("notificationFilter", function() {
            return function(notifications, filterText) {
                if (!filterText) {
                    return notifications;
                }
                var filteredNotifications = [];
                filterText = filterText.toLocaleLowerCase();
                angular.forEach(notifications, function(notification) {
                    var system_name = notification.system_name.toLocaleLowerCase();
                    var display_name = notification.display_name.toLocaleLowerCase();

                    if (system_name.indexOf(filterText) !== -1) {
                        filteredNotifications.push(notification);
                    } else if (display_name.indexOf(filterText) !== -1) {
                        filteredNotifications.push(notification);
                    }
                });

                return filteredNotifications;
            };
        });

        /**
         * Filter for services associated with a notification
         * @param  {onject} item
         * @return {array}
         */
        app.filter("notificationServiceFilter", function() {
            return function(services, notificationImportance) {
                if (typeof notificationImportance === "undefined") {
                    return services;
                }
                var filteredServices = [];
                angular.forEach(services, function(service) {
                    var service_level = Number(service.level);
                    if ( Number(notificationImportance) !== 0 && service_level !== 0 && service_level >= notificationImportance ) {
                        filteredServices.push(service);
                    }
                });

                return filteredServices;
            };
        });
    }
);

/*
# templates/contact_manager/filters/splitOnComma.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/splitOnComma',[
        "angular"
    ],
    function(angular) {

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Filter to split comma delimited strings
         * @param  {string} input
         * @param  {number} limit
         * @return {array}
         */
        app.filter("splitOnComma", function() {
            return function(input, limit) {

                // If it's not a string we got an array somehow, lets punt it back
                if (typeof input !== "string" ) {
                    return input;
                }

                // If no comma, lets also punt it
                var commaRegex = new RegExp(",");
                if (!commaRegex.test(input)) {
                    return [input];
                }

                // We use 5 as a default since this will give 3 + message about more listed
                limit = limit || 5;

                // This assume we are using a comma delimited list, this will break if strings with commas are valid
                var items = input.split(",");

                if ( items.length < limit ) {
                    return items;
                } else {

                    // If the limit is 5 we want to always use 4 or less lines, since the message takes up one
                    // this means we do limit-2
                    var newItems = items.slice(0, limit - 2);
                    newItems.push(LOCALE.maketext(" … and [numf,_1] more", (items.length - (limit - 2))));

                    return newItems;
                }
            };
        });

        /**
         * Filter to split comma delimited strings for title attribute
         * @param  {string} input
         * @return {string}
         */
        app.filter("splitOnCommaForTitle", function() {
            return function(input) {

                // If it's not a string we got an array somehow, lets punt it back
                if (typeof input !== "string" ) {
                    return input;
                }

                // If no comma, lets also punt it
                var commaRegex = new RegExp(",");
                if (!commaRegex.test(input)) {
                    return input;
                }

                var items = input.split(",");
                return items.join(",\n");
            };
        });
    }
);

/*
# templates/contact_manager/services/VerifyNotificationService.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/verifyNotificationService',[

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


        app.factory("verifyNotificationService", ["$q", "APIService",
            function($q, APIService) {

                // Set up the service's constructor and parent
                var BaseService = function() {};
                BaseService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(BaseService.prototype, {

                    /**
                     * get forward location for provided user
                     *
                     * @method
                     * @param  {String}
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    verify_service: function(verification_api) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, verification_api);

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
# templates/contact_manager/services/indexService.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */


define(
    'app/services/indexService',[

        // Libraries
        "angular",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
    ],
    function(angular, APIREQUEST) {

        var app = angular.module("whm.contactManager.indexService", ["cjt2.services.apicatcher"]);

        var NO_MODULE = "";

        function indexServiceFactory(PAGE, api) {
            var indexService = {};

            /**
             * Create a User Session to transfer to cPanel
             *
             * @method createUserSession
             *
             * @return {Promise.<string,Error>} returns the string url to redirect to
             *
             */

            indexService.createUserSession = function() {

                var apicall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "create_user_session",
                    {
                        "user": PAGE.REMOTE_USER,
                        "service": "cpaneld",
                        "app": "ContactInfo_Change"
                    }
                );

                return api.promise(apicall).then(function(result) {
                    return result.data.url;
                });
            };

            return indexService;
        }

        indexServiceFactory.$inject = ["PAGE", "APICatcher"];
        return app.factory("indexService", indexServiceFactory);
    });

/*
# templates/contact_manager/controllers/MainController.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W003 */

define(
    'app/controllers/mainController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/filters/notificationFilter",
        "app/filters/splitOnComma",
        "app/services/verifyNotificationService",
        "app/services/indexService",
        "cjt/directives/spinnerDirective",
    ],
    function(angular, _, LOCALE) {

        var app;
        try {
            app = angular.module("App"); // For runtime
            app.value("PAGE", window.app.PAGE);
            app.value("LOCALE", LOCALE);
            app.value("_", _);
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        var MainController = function($scope, $filter, $window, PAGE, growl, verifyNotificationService, indexService, LOCALE, spinnerAPI, _) {
            var _this = this;
            var orderBy = $filter("orderBy");
            var notificationFilter = $filter("notificationFilter");

            _this.filteredNotifications = [];
            _this.selectedNotifications = [];

            _this.PAGE = PAGE;
            _this.meta = {
                current_sort_key: "importance",
                reverse_sort: false,
                search_key: "",
            };

            if ( _this.PAGE["event"] ) {
                _this.meta.search_key = _this.PAGE["event"];
                _this.show_notifications = true;
            }

            _this.locale = LOCALE;

            _this.will_verify = false;

            for (var x = 0; x < PAGE.contactmethods.length; x++ ) {
                if (PAGE.contactmethods[x].verification_api && PAGE.contactmethods[x].contact) {
                    _this.will_verify = true;
                    break;
                }
            }

            _this.orderNotifications = function(key) {
                if (_this.meta.current_sort_key === key) {
                    _this.meta.reverse_sort = !_this.meta.reverse_sort;
                } else {
                    _this.meta.reverse_sort = 0;
                    _this.meta.current_sort_key = key;
                }

                _this.updateFilteredNotifications();
            };

            /**
             * Creates a cPanel session and then redirects to it in a new window
             *
             * @method loginTocPanel
             *
             */

            _this.loginTocPanel = function() {
                return indexService.createUserSession().then(function(loginUrl) {
                    if (!$window.open(loginUrl, "_blank")) {
                        growl.success(LOCALE.maketext("Click to continue as the “[_1]” user and modify the [asis,cPanel] notification settings.", _.escape(PAGE.REMOTE_USER)), {
                            ttl: -1,
                            variables: {
                                buttonLabel: LOCALE.maketext("Go to [asis,cPanel]"),
                                showAction: true,
                                action: function() {
                                    $window.open(loginUrl);
                                }
                            }
                        });
                    }
                });
            };

            _this.updateFilteredNotifications = function() {
                _this.filteredNotifications = orderBy(notificationFilter(_this.PAGE.notifications, _this.meta.search_key), _this.meta.current_sort_key, _this.meta.reverse_sort);
            };

            _this.verify_service = function(contactMethod) {
                contactMethod.verifying = true;

                spinnerAPI.start(contactMethod.system_name + "-spinner");

                // verify_{{contactMethod.system_name}}
                return verifyNotificationService.verify_service(contactMethod.verification_api)
                    .then(function(results) {

                        // Handle the multiple returns from pushbullet(may be used by multiple other services later)
                        if (results.data && results.data.length) {
                            angular.forEach(results.data, function(o) {
                                if (o.result.error) {
                                    growl.error(_this.locale.maketext("The system was unable to send the [_1] notification to “[_2]” because of the following error: [_3]", _.escape(contactMethod.display_name), _.escape((o.url || o.access_token)), _.escape(o.result.error)));
                                } else {
                                    growl.success(_this.locale.maketext("The system sent the [_1] notification message “[_2]” successfully to “[_3]”.", _.escape(contactMethod.display_name), _.escape(o.result.message_id), _.escape((o.url || o.access_token))));
                                }
                            });
                        } else { // if not passing back an array but instead just simple success
                            growl.success(_this.locale.maketext("The system sent the [_1] notification message “[_2]” successfully.", _.escape(contactMethod.display_name), _.escape(results.data.message_id)));
                        }
                    }, function(error) {
                        growl.error(_this.locale.maketext("The system was unable to send the [_1] notification because of the following error: [_2]", _.escape(contactMethod.display_name), _.escape(error)));
                    }).finally(function() {
                        contactMethod.verifying = false;
                        spinnerAPI.stop(contactMethod.system_name + "-spinner");
                    });
            };

            _this.orderNotifications("display_name");

            $scope.$watch(function() {
                return _this.filteredNotifications;
            }, function(newVal) {
                _this.selectedNotifications = $filter("filter")(newVal, {
                    selected: true
                });
            }, true);

            return _this;
        };

        MainController.prototype.setSelected = function(dataset, selected) {
            angular.forEach(dataset, function(o) {
                o.selected = selected;
            });
        };

        MainController.prototype.setLevel = function(dataset, level) {
            angular.forEach(dataset, function(o) {
                if (!o.disabled ) {
                    o.importance = level.toString();
                }
            });
        };

        MainController.prototype.selectedHeaderClass = function(column, tableMeta) {
            var className = "icon-arrow-" + (tableMeta.reverse_sort ? "down" : "up");
            return column === tableMeta.current_sort_key && className;
        };


        MainController.$inject = ["$scope", "$filter", "$window", "PAGE", "growl", "verifyNotificationService", "indexService", "LOCALE", "spinnerAPI", "_"];
        var controller = app.controller("MainController", MainController);

        return controller;
    }
);

/*
# templates/contact_manager/directives/indeterminate.js   Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/indeterminate',[
        "angular"
    ],
    function(angular) {

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Angular directive that when attached to a checkbox will set indeterminate based on the passed in value.
         * This is sugar since we cannot set this attribute in HTML directly.
         */
        app.directive("cpIndeterminate", [

            function() {
                return {
                    restrict: "A",
                    scope: {
                        cpIndeterminate: "@",
                    },

                    link: function(scope, elem) {
                        scope.$watch("cpIndeterminate", function(newVal) {
                            var booleanVal = false;
                            if (newVal === "true") {
                                booleanVal = true;
                            }
                            elem.prop("indeterminate", booleanVal);
                        });

                    }
                };
            }
        ]);
    }
);

/*
# templates/contact_manager/index.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require:false, define:false */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "uiBootstrap",
        "cjt/directives/searchDirective",
        "cjt/modules",
        "cjt/decorators/growlDecorator",
    ],
    function(angular, CJT) {
        "use strict";

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "cjt2.directives.search",
                "cjt2.whm",
                "angular-growl",
                "whm.contactManager.indexService"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/controllers/mainController",
                    "app/directives/indeterminate",
                ], function(BOOTSTRAP) {

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

