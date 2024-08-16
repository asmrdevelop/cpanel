/* backup_configuration/services/validationLog.js   Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [

        // Libraries
        "angular",
        "lodash",

        // CJT
        "cjt/core",
        "cjt/util/locale",
        "cjt/services/alertService",
    ],
    function(angular, _, CJT, LOCALE, alertService) {
        "use strict";

        var module = angular.module("whm.backupConfiguration.validationLog.service", []);

        /**
         * Setup validation log service
         */
        module.factory("validationLog", ["$window", "alertService", function($window, alertService) {

            /** List of validation log items for backup destinations. */
            var logEntries = [];

            /* Represents basic information used to record the
             * current validation state for a remote backup destination.
             *
             * @param source {Object} generic destination object or ValidationLogItem
             */
            function ValidationLogItem(source) {
                if (typeof source !== "object") {
                    return;
                }

                // if the source object contains the destinationId
                // property, it is an existing ValidationLogItem,
                // possibly lacking defined methods
                if (source.hasOwnProperty("destinationId")) {
                    this.cloneProperties(source);
                } else {
                    this.name = source.name;
                    this.destinationId = source.id;
                    this.transport = source.type;
                    this.status = "running";
                    this.updateBeginTime();
                }

                if (this.status === "running") {
                    ValidationLogItem.inProgress++;
                }
            }

            /** Static property to allow easy access to log items by destination ID.
             */
            ValidationLogItem.quickAccess = {};

            /** Static property to maintain count of in progress validations.
             *  This avoids excessive looping over the list of validations,
             *  looking for those with a status of "running".
             */
            ValidationLogItem.inProgress = 0;

            /**
             * Update the quick access hash with revised log items (static).
             *
             * @method updateQuickAccess
             * @param newLogItemList {Array} list of log items
             */
            ValidationLogItem.updateQuickAccess = function(newLogItemList) {
                ValidationLogItem.quickAccess = {};
                if (Array.isArray(newLogItemList) && newLogItemList.length > 0) {
                    newLogItemList.forEach(function(item) {
                        if (typeof (item) === "object" &&
                        item.hasOwnProperty("destinationId")) {
                            ValidationLogItem.quickAccess[item.destinationId] = item;
                        }
                    });
                }
            };

            /**
             * Retrieve status from quick access hash.
             *
             * @method getStatusFor
             * @param {string} id - destination id for log item of interest
             * @return {ValidationLogItem}
             */
            ValidationLogItem.getStatusFor = function(id) {
                if (ValidationLogItem.quickAccess.hasOwnProperty(id)) {
                    return ValidationLogItem.quickAccess[id].status;
                }
                return null;
            };

            /**
             * Given an existing object, copy its properties into this ValidationLogItem.
             * This is used to create complete objects from serialized objects stored in
             * a JSON data structure. JSON does not support methods.
             *
             * @method cloneProperties
             * @param {Object} noFunctionObject
             */
            ValidationLogItem.prototype.cloneProperties = function(noFunctionObject) {
                for (var property in noFunctionObject) {
                    if (noFunctionObject.hasOwnProperty(property)) {
                        this[property] = noFunctionObject[property];
                    }
                }
            };

            /**
             * Update the begin time stamp for a validation run.
             * Also, creates a formatted time for display.
             *
             * @method updateElapsedTime
             */
            ValidationLogItem.prototype.updateBeginTime = function() {
                var start = new Date();
                this.beginTime = Date.now();
                start.setTime(this.beginTime);
                this.formattedBeginTime = start.toLocaleTimeString();
            };

            /**
             * Reset the elapsed time validation log item.
             *
             * @method resetElapsedTime
             */
            ValidationLogItem.prototype.resetElapsedTime = function() {
                delete this.endTime;
                delete this.elapsedTime;
                delete this.alert;
                delete this.formattedElapsedTime;
                this.status = "running";
                ValidationLogItem.inProgress++;
            };

            /**
             * Generate the elapsed time for a completed validation run.
             * Also, creates a formatted string for display purposes.
             *
             * @method generateElapsedTime
             */
            ValidationLogItem.prototype.generateElapsedTime = function() {
                this.endTime = Date.now();
                this.elapsedTime = this.endTime - this.beginTime;
                this.formattedElapsedTime = LOCALE.maketext("[_1] [numerate,_1,second,seconds]", Math.round(this.elapsedTime / 1000));
            };

            /**
             * Updates a ValidationLogItem to indicate that the in progress
             * validation has completed.
             *
             * @method markAsComplete
             */
            ValidationLogItem.prototype.markAsComplete = function(alert) {
                this.generateElapsedTime();
                if (alert.type === "success") {
                    this.status = "success";
                } else {
                    this.status = "failure";
                }

                ValidationLogItem.inProgress--;

                this.alert = alert;
            };

            /**
             * Adds a ValidationLogItem to an existing array. If the item
             * already exists, it is reset to initial settings.
             *
             * @method addTo
             * @param {Array} itemList - array to which to add log item.
             * @return {boolean} true = suceesfully added; false = already there or parameter is not
             * an array
             */
            ValidationLogItem.prototype.addTo = function(itemList) {
                if (Array.isArray(itemList)) {
                    if (!ValidationLogItem.quickAccess.hasOwnProperty(this.destinationId)) {
                        itemList.push(this);
                        ValidationLogItem.quickAccess[this.destinationId] = this;
                        return true;
                    } else {
                        this.status = "running";
                        this.updateBeginTime();
                        this.resetElapsedTime();
                    }
                }
                return false;
            };

            // return the factory interface
            return {

                /**
                 * Get the list of validation log entries.
                 *
                 * @method getLogEntries
                 * @return {array} - array of validation log entries
                 */
                getLogEntries: function() {
                    if (logEntries.length === 0) {

                        // check to see whether there is there is a session cache of validation log entries
                        var sessionCache = $window.sessionStorage.getItem("destination_validation_log");
                        if (sessionCache) {
                            var cachedLogEntries = JSON.parse(sessionCache);
                            cachedLogEntries.forEach(function(entry) {
                                logEntries.push(new ValidationLogItem(entry));
                            });
                        }
                        ValidationLogItem.updateQuickAccess(logEntries);
                    }
                    return logEntries;
                },

                /**
                 * Create a cache of the validation log items using sessionStorage.
                 *
                 * @method cacheLogEntries
                 */
                cacheLogEntries: function() {
                    $window.sessionStorage.setItem("destination_validation_log", JSON.stringify(logEntries));
                },

                /**
                 * Clear the cache of the validation log items stored in sessionStorage.
                 *
                 * @method clearCache
                 */
                clearCache: function() {
                    $window.sessionStorage.removeItem("destination_validation_log");
                },

                /**
                 * Are there entries in the validation log.
                 *
                 * @method hasLogEntries
                 * @return {boolean} - true if populated; false if not
                 */
                hasLogEntries: function() {
                    return logEntries && logEntries.length > 0;
                },

                /**
                 * Update name for a given Id. Called when
                 * updating a destination in case of potential changes affecting
                 * a validation log record.
                 *
                 * @method updateValidationInfo
                 * @param {string} destinationId - unique id of destination that was changed
                 * @param {string} newName - potentially updated name
                 */
                updateValidationInfo: function(destinationId, newName) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(destinationId)) {
                        ValidationLogItem.quickAccess[destinationId].name = _.escape(newName);
                    }
                },

                /**
                 * Add new validation information to the log for a given destination.
                 *
                 * @method add
                 * @param {Object} - validatingDestination the destination being validated
                 */
                add: function(validatingDestination) {
                    var validating = null;
                    if (ValidationLogItem.quickAccess.hasOwnProperty(validatingDestination.id)) {
                        validating = ValidationLogItem.quickAccess[validatingDestination.id];
                        validating.resetElapsedTime();
                        validating.updateBeginTime();
                    } else {
                        validating = new ValidationLogItem(validatingDestination);
                        validating.addTo(logEntries);
                        ValidationLogItem.quickAccess[validating.destinationId] = validating;
                    }
                    this.cacheLogEntries();
                },

                /**
                 * Remove validation information from the log for a given destination.
                 *
                 * @method remove
                 * @param {string} - destinationId - the destination id to remove from the log
                 */
                remove: function(destId) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(destId)) {
                        var itemToRemove = ValidationLogItem.quickAccess[destId];
                        if (itemToRemove.status === "running") {
                            ValidationLogItem.inProgress--;
                        }
                        delete ValidationLogItem.quickAccess[destId];
                        _.remove(logEntries, function(item) {
                            return item.destinationId === destId;
                        });
                        this.cacheLogEntries();
                    }
                },

                /**
                * Is validation in progress for given destination.
                *
                * @method isValidationInProgressFor
                * @param {String} id - id of specific destination to test
                * @returns {Boolean} is destination being validated
                */
                isValidationInProgressFor: function(destination) {
                    if (ValidationLogItem.getStatusFor(destination.id) === "running") {
                        return true;
                    }

                    return false;
                },

                /**
                * Determine whether a validation process is current running.
                *
                * @method isValidationRunning
                * @returns {Boolean} is validation (multiple or single) process running
                */
                isValidationRunning: function() {
                    return ValidationLogItem.inProgress > 0;
                },

                /**
                * Get count of inProgress validations.
                *
                * @method getInProgressCount
                * @returns {number} the current count of in progress validations.
                */
                getInProgressCount: function() {
                    return ValidationLogItem.inProgress;
                },

                /**
                * Gets the current status of the validation process
                * for a given destination id.
                *
                * @method validateAllStatus
                * @param {String} id - unique identification string
                * @return {String} - status string (running | success | failure)
                */
                validateAllStatus: function(id) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(id)) {
                        return ValidationLogItem.quickAccess[id].status;
                    }
                    return null;
                },

                /**
                * Checks whether the validation process for a particular
                * destination succeeded.
                *
                * @method validateAllSuccessFor
                * @param {String} id - unique identification string
                */
                validateAllSuccessFor: function(id) {
                    return this.validateAllStatus(id) === "success";
                },

                /**
                * Checks whether the validation process for a particular
                * destination failed.
                *
                * @method validateAllFailureFor
                * @param {String} id - unique identification string
                */
                validateAllFailureFor: function(id) {
                    return this.validateAllStatus(id) === "failure";
                },

                /**
                * Updates the status of an existing Validation Log Item.
                *
                * @method markAsComplete
                * @param {String} id - unique identification string
                * @param {Object} alertOptions - details of validation result
                */
                markAsComplete: function(id, alertOptions) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(id)) {
                        ValidationLogItem.quickAccess[id].markAsComplete(alertOptions);
                        this.cacheLogEntries();
                    }
                },

                /**
                 * Displays alert message for validation result
                 *
                 * @method showValidationMessageFor
                 * @param {String} id - unique identification string
                 */
                showValidationMessageFor: function(id) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(id) && ValidationLogItem.quickAccess[id].hasOwnProperty("alert")) {
                        alertService.add(ValidationLogItem.quickAccess[id].alert);
                    }
                },
            };
        }]);
    }
);
