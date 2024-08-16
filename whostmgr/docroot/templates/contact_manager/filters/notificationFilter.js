/*
# templates/contact_manager/filters/notificationFilter.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
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
