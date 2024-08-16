/*
# validator-utils.js                                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * The module contains utility functions for validators
 *
 * @module validator-utils
 */
define([], function() {
    "use strict";

    // NOTE: Having results contain multiple messages add a lot of complication to the system since
    // the validation system already has a system for registering multiple messages. I think we should
    // refactor this to remove this complication as its us is very edge case and makes renders much more
    // complicated.

    /**
     * The results object is used by all of the custom validator to embed response messages generated
     * by complex validation logic.
     *
     * @constructor
     */
    var ValidationResult = function() {
        this.isValid = true;
        this.messages = [];
        this.lookup = {};
    };

    ValidationResult.prototype = {

        /**
         * Converts the message collection into a delimited string
         *
         * @method  toString
         * @param  {String} [delimiter] Optional delimiter, defaults to newline.
         * @return {String}             Message from the has concatenated with delimiter separations.
         */
        toString: function(delimiter) {
            delimiter = delimiter || "\n";
            var message = "";
            for (var i = 0, l = this.messages.length; i < l; i++) {
                var item = this.messages[i];
                if (item && i > 0) {
                    message += delimiter;
                }
                message += item.message;
            }
            return message;
        },

        /**
         * Checks if the message collection contains an item for the given name.
         *
         * @method hasMessage
         * @param  {String}  name Name of the message set by the validator.
         * @return {Boolean}      true if there is a message with that name, false otherwise.
         */
        hasMessage: function(name) {
            var item = this.lookup[name];
            return typeof (item) !== "undefined";
        },

        /**
         * Checks if the message collection contains any messages.
         *
         * @method hasMessages
         * @return {Boolean} [description]
         */
        hasMessages: function() {
            return this.messages.length > 0;
        },

        /**
         * Add a message for this validator
         *
         * @method add
         * @param {String} name      A short name for the validation rule that triggered the message
         * @param {String} message   The actual message text
         */
        add: function(name, message) {
            var obj = { name: name, message: message };
            this.messages.push(obj);
            this.lookup[name] = obj; // NOTE: The lookup only supports one message per name. Last message added wins.
            return this;
        },

        /**
         * Shortcut for the "add" method when the validation message results from an error.
         *
         * @method addError
         * @param  {String} name        A short name for the validation rule that triggered the error
         * @param  {String} message     A longer description of the error
         * @return {ValidationResult}   This object, for chaining
         */
        addError: function(name, message) {
            this.add(name, message);
            this.isValid = false;
            return this;
        },

        /**
         * Clear all the messages from the ValidationResult object.
         *
         * @method clear
         * @return {ValidationResult}   This object, for chaining
         */
        clear: function() {
            this.messages = [];
            this.lookup = {};
            this.isValid = true;
            return this;
        },

        /**
         * Gets all the messages or a single message by name.
         *
         * @method get
         * @param  {String} [name] Optional validator name.
         * @return {Object|Array}
         *         {String} .name - Name of the validator that placed the message
         *         {String} .message - Message output by the specific validator.
         */
        get: function(name) {
            if (typeof (name) === "string") {
                return this.lookup[name];
            } else {
                return this.messages;
            }
        }
    };

    /**
     * Attached to each ngModelDirective is an $error_details member of this type.
     * This collection contains the results for each validator attached to a ngModelDirective.
     * @constructor
     */
    var ExtendedModelReporting = function() {
        this.data = [];
        this.lookup = {};
    };

    ExtendedModelReporting.prototype = {

        /**
         * Fetch the extended validation information for a given validator
         *
         * @method get
         * @param  {String} valName Name of the validator
         * @return {ValidationResult}         ValidationResult object for the validator.
         */
        get: function(valName) {
            return this.lookup[valName];
        },

        /**
         * Set a ValidationResult for a specific validator.
         *
         * @method set
         * @param {String} valName Name of the validator
         * @param {ValidationResult} result  ValidationResult object for the validator.
         */
        set: function(valName, result) {
            this.data.push(result);
            this.lookup[valName] = result;
        },

        /**
         * Remove a result for a specific validator
         *
         * @method remove
         * @param {String} valName Name of the validator
         */
        remove: function(valName) {
            if (!this.data.length) {
                return;
            }

            var item = this.lookup[valName];

            for (var index = this.data.length - 1; index >= 0; index--) {
                if (this.data[index] === item) {
                    this.data.splice(index, 1);
                }
            }
            delete this.lookup[valName];
        },

        /**
         * Check if there are any results objects stored here.
         *
         * @method  hasResults
         * @return {Boolean} true if there are results, false otherwise.
         */
        hasResults: function() {
            return this.data.length > 0;
        },

        /**
         * Clear the data so we can recalculate
         */
        clear: function() {
            this.data = [];
            this.lookup = {};
        }
    };

    /**
     * Attached to each ngFormDirective is an $error_details member of this type.
     * This collection contains the results for each field and for each validator attached to a ngFormDirective.
     * @constructor
     */
    var ExtendedFormReporting = function() {
        this.data = {};
    };

    ExtendedFormReporting.prototype = {

        /**
         * Fetch the results for a field and validator.
         *
         * @method get
         * @param  {String} fieldName Name of the field.
         * @param  {String} valName   Name of the validator.
         * @return {ValidationResult}           ValidationResult object for the validator.
         */
        get: function(fieldName, valName) {
            var field = this.data[fieldName] || new ExtendedModelReporting();
            if (valName) {
                return field.get(valName);
            } else {
                return field;
            }
        },

        /**
         * Set the results for a field and validator.
         *
         * @method set
         * @param  {String} fieldName Name of the field.
         * @param  {String} valName   Name of the validator.
         * @param  {ValidationResult}           ValidationResult object for the validator.
         */
        set: function(fieldName, valName, result) {
            this.data[fieldName] = this.data[fieldName] || new ExtendedModelReporting();
            this.data[fieldName].set(valName, result);
            return this;
        },

        /**
         * Remove the results for a field and validator.
         *
         * @method remove
         * @param  {String} fieldName Name of the field.
         * @param  {String} valName   Name of the validator.
         */
        remove: function(fieldName, valName) {
            if (this.data[fieldName]) {
                this.data[fieldName].remove(valName);
                if (!this.data[fieldName].hasResults()) {
                    this.data[fieldName] = null;
                    delete this.data[fieldName];
                }
            }
        }
    };

    return {

        // Unit Testing Only
        ValidationResult: ValidationResult,
        ExtendedModelReporting: ExtendedModelReporting,
        ExtendedFormReporting: ExtendedFormReporting,

        // Public API

        /**
         * Helper method to create a result structure in a uniform way.
         * @param {Boolean} [clear] Optional, clear the same item if is true so it does not accumulate messages.
         *                          Otherwise accumulate the messages.
         * @return {ValidationResult}
         *             {Boolean} .isValid  - true if the results represents a valid value, false otherwise.
         *             {Object}  .messages - Hash of key/message pairs
         */
        initializeValidationResult: function(clear) {
            var result = new ValidationResult();
            if (clear) {
                result.clear = true;
            }
            return result;
        },

        /**
         * Initialize the extended error reporting objects.
         * @param  {ModelController} ctrl  Model controller managing the data.
         * @param  {FormController} [form] Optional form controller.
         */
        initializeExtendedReporting: function(ctrl, form) {
            ctrl.$error_details = new ExtendedModelReporting();
            if (form) {
                form.$error_details = new ExtendedFormReporting();
            } else {
                if (window.console) {
                    window.console.log("To participate in extended form validation you must have a ngForm or form around your controls with custom validation.");
                }
            }
        },

        /**
         * Update a collection of possible error messages. This is use for multi-error aggregate validators.
         *
         * @param  {ModelController} ctrl  Model controller managing the data.
         * @param  {FormController} [form] Optional form controller.
         * @param  {String[]} names - List of validator names to check.
         * @param  {ValidationResult} multiResult
         */
        updateExtendedReportingList: function(ctrl, form, names, multiResult) {
            names.forEach(function(name) {
                var error = multiResult.lookup[name];
                if (error) {
                    var result = new ValidationResult();
                    result.add(error.name, error.message);
                    this.updateExtendedReporting(multiResult.isValid, ctrl, form, name, result);
                }
            }, this);
        },

        /**
         * Updates the extended reporting based on the validity of the
         * value for a specific field validator.
         *
         * @param  {Booelan} valid  true if the model is valid, false otherwise.
         * @param  {ModelController} ctrl  Model controller managing the data.
         * @param  {FormController} [form] Optional form controller.
         * @param  {String} name
         * @param  {ValidationResult} result
         */
        updateExtendedReporting: function(valid, ctrl, form, name, result) {
            if (!valid) {
                if (result.clear) {
                    ctrl.$error_details.remove(name);
                    if (form) {
                        form.$error_details.remove(ctrl.$name, name);
                    }
                }
                ctrl.$error_details.set(name, result);
                if (form) {
                    form.$error_details.set(ctrl.$name, name, result);
                }
            } else {
                ctrl.$error_details.remove(name);
                if (form) {
                    form.$error_details.remove(ctrl.$name, name);
                }
            }
        }
    };
});
