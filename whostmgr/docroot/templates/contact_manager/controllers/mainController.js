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
    [
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
