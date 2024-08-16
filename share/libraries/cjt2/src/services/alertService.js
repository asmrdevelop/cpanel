/*
# cjt/services/alertService.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [

        // Libraries
        "angular",
        "cjt/core"
    ],
    function(angular, CJT) {

        "use strict";

        var module = angular.module("cjt2.services.alert", []);

        /**
         * The alert service provides an API for handling a collection of alerts. The alertList directive
         * uses the data from this service to render a list of alerts.
         */
        module.factory("alertService", function() {

            var alerts = {
                    __DEFAULT: []
                },
                alertCounter = 0;

            /**
             * Retrieves the alert list for a particular alert group
             *
             * @method getAlerts (aliased as bind in the public interface)
             * @param {String|Number} group     A group name that should correspond to a key in alerts
             * @return {Array} alerts
             */
            function getAlerts(group) {
                if (group) {
                    group = group.toString();

                    if (alerts[group]) {
                        return alerts[group];
                    } else {
                        alerts[group] = [];
                        return (alerts[group]);
                    }
                } else {
                    return alerts.__DEFAULT;
                }
            }


            /**
             * Validate the type passed in to the alerts before adding it.
             *
             * @method  _validateType
             * @private
             * @param  {String} type    Type requested from the outside.
             * @return {Boolean}        true if a recognized type, false otherwise.
             */
            function _validateType(type) {
                switch (type) {
                    case "danger":
                    case "warning":
                    case "success":
                    case "info":
                        return true;
                    default:
                        return false;
                }
            }

            function _getAlertObject(alert) {
                if (typeof alert === "string") {
                    alert = {
                        message: alert
                    };
                } else if (typeof alert === "object" && typeof alert.message !== "string") {
                    throw new TypeError("alertService: alert.message is expected to be a string");
                }
                return alert;
            }

            function success(alert) {
                var successDefaults = {
                    autoClose: 10 * 1000,
                    type: "success"
                };
                alert = _getAlertObject(alert);
                add(angular.extend(successDefaults, alert));

            }


            /**
             * Add an alert to the alerts service
             *
             * @method add
             * @param {String|Object} alert     A warning string or an alert object with the following properties:
             *  @param {String} message         The text to be displayed in the alert
             *  @param {String} type            The type of alert to display: success, info, warning, danger, defaults to warning
             *  @param {String} id              Static id for the alert
             *  @param {String|Number} group    A group name that can refer to related alerts
             *  @param {Boolean} replace        Bypass the default behavior of replacing existing alerts with false
             *  @param {Number} [autoClose]     Number of milliseconds until auto-closes the alert.
             */
            function add(alert) {

                alert = _getAlertObject(alert);

                // Determine proper ID to use
                var uniqueID;
                var idIsGenerated;
                if (typeof alert.id === "string") {

                    // Use the id provided
                    uniqueID = alert.id;
                } else {

                    // Generate an id
                    uniqueID = "alert" + alertCounter++;
                    idIsGenerated = true;
                }

                // Check if a group is specified, a valid key, and exists
                var group = "__DEFAULT";
                if (typeof alert.group === "string" || typeof alert.group === "number") {
                    group = alert.group.toString();
                    if (!alerts[group]) {
                        alerts[group] = [];
                    }
                }

                // Stack or replace alerts
                if (!alert.hasOwnProperty("replace") || alert.replace) {
                    clear(void 0, group);
                } else if (!idIsGenerated) {

                    // If we're not replacing the existing alerts, we might want to append a counter to the ID.
                    //   If the ID is generated, then we already have a counter so don't add another one.
                    //   If the ID is not generated, we will add a counter unless alert.counter exists and is falsy.
                    alert.counter = !alert.hasOwnProperty("counter") || !!alert.counter;
                    if (alert.counter) {
                        uniqueID += alertCounter++;
                    }
                }

                alerts[group].push({
                    type: _validateType(alert.type) ? alert.type : "warning",
                    closeable: angular.isDefined(alert.closeable) ? alert.closeable : alert.type !== "danger",
                    message: alert.message,
                    list: alert.list || [],
                    id: uniqueID,
                    autoClose: CJT.isE2E() ? false : alert.autoClose,
                    label: alert.label
                });
            }


            /**
             * Remove an alert from the alerts service
             *
             * @method remove
             * @param {String} index            The array index of the alert to remove
             * @param {String|Number} group     A valid identifier that serves as a group name
             */
            function remove(index, group) {
                var alertGroup = getAlerts(group);
                alertGroup.splice(index, 1);
            }


            /**
             * Remove an alert by its unique id
             *
             * @method removeById
             * @param  {String} id    Id of the alert
             * @param  {String} group Group name
             * @return {Boolean}      true if found and removed, false otherwise
             */
            function removeById(id, group) {
                var alertGroup = getAlerts(group);
                for (var i = 0, l = alertGroup.length; i < l; i++) {
                    if (alertGroup[i].id === id) {
                        alertGroup.splice(i, 1);
                        return true;
                    }
                }
                return false;
            }

            /**
             * Removes all alerts or all alerts of a specified type
             *
             * @method clear
             * @param {String} type     The type of alert to clear from the alert list
             */
            function clear(type, group) {
                var alertGroup = getAlerts(group);

                if (type) {

                    // Loop over the array and filter out the specified type
                    // Start iterating from the last element
                    for (var i = alertGroup.length - 1; i >= 0; i--) {
                        if (alertGroup[i].type === type) {
                            alertGroup.splice(i, 1);
                        }
                    }
                } else {

                    // Remove all alerts while maintaining the array reference so
                    // that any bound elements will continue to update properly
                    alertGroup.splice(0);
                }
            }

            // return the factory interface
            return {
                getAlerts: getAlerts,
                add: add,
                success: success,
                remove: remove,
                removeById: removeById,
                clear: clear
            };
        });
    }
);
