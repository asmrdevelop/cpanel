/*
# api/io/base.js                                  Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

// TODO: Add tests for these

/**
 * Contain the IAPI Driver implementation used to process cpanel api2
 * request/response messages.
 * @module cjt/io/api2
 * @example
 *
 */
define(["lodash", "cjt/util/locale"], function(_, LOCALE) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/base"; // requirejs(["cjt/io/base"], function(base) {}); -> cjt/io/base.js || cjt/io/base.debug.js
    var MODULE_DESC = "Contains helper methods reused by all the api drivers.";
    var MODULE_VERSION = 2.0;

    // ------------------------------
    // State
    // ------------------------------
    var _transaction_args = {};

    /**
     * This static class contains various helper methods that are used by drivers.
     * @class  api_base
     * @static
     * @type {Object}
     */
    var base = {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,

        /**
         * It is useful for error reporting to show a failed transaction's arguments,
         * so CPANEL.api stores these internally for later reporting.
         *
         * @method get_transaction_args
         * @public
         * @static
         * @param {number} t_id The transaction ID (as given by YUI 2 asyncRequest)
         * @return {object} A copy of the "arguments" object
         */
        get_transaction_args: function(t_id) {
            var args = _transaction_args[t_id];
            return args && _.extend({}, args); // shallow copy
        },

        /**
         * Generates an unknown error message.
         *
         * @method _unknown_error_msg
         * @protected
         * @static
         * @return {String} Localized erroror message.
         */
        _unknown_error_msg: function() {
            return LOCALE.maketext("An unknown error occurred.");
        },

        /**
         * Parse the response object and normalize it.
         *
         * @method _parse_response
         * @protected
         * @static
         * @param  {Function} status_finder  Function that extracts the status from the object representation
         * @param  {Function} message_finder Function that extracts the message collection from the object representation
         * @param  {Function} data_getter    Function that extracts the data from the object representation
         * @param  {Function} meta_getter    Function that extracts the meta data from the object representation
         * @param  {String}   response       Raw JSON response from the io system
         * @return {Function}                Parsed response
         */
        _parse_response: function(iapi_module, response) {
            var error = null;
            if (_.isString(response)) {
                try {
                    response = JSON.parse(response);
                } catch (e) {
                    if (window.console) {
                        window.console.log("Could not parse the response string: " + response + "\n" + e);
                    }
                    error = LOCALE.maketext("The API response could not be parsed.");
                    response = null;
                }
            }

            return base._parse_response_object(iapi_module, response, error);
        },

        /**
         * Parse the response object and normalize it.
         *
         * @method _parse_response_object
         * @protected
         * @static
         * @param  {Function} status_finder  Function that extracts the status from the object representation
         * @param  {Function} message_finder Function that extracts the message collection from the object representation
         * @param  {Function} data_getter    Function that extracts the data from the object representation
         * @param  {Function} meta_getter    Function that extracts the meta data from the object representation
         * @param  {Object}   response       Raw JSON response from the io system
         * @return {Function}                [description]
         */
        _parse_response_object: function(iapi_module, response, error) {
            var status_finder = iapi_module.find_status;
            var message_finder = iapi_module.find_messages;
            var data_getter = iapi_module.get_data;
            var meta_getter = iapi_module.get_meta;

            var data = null,
                meta = null,
                status = false,
                messages = null;

            try {
                data = data_getter(response);
                if (_.isUndefined(data)) {
                    data = null;
                }
            } catch (e) {
                if (window.console) {
                    window.console.log("Failed to extract the data from the response: ", response, e);
                }
            }

            try {
                meta = meta_getter(response);
                if (_.isUndefined(meta)) {
                    meta = null;
                }
            } catch (e) {
                if (window.console) {
                    window.console.log("Failed to extract the metadata from the response: ", response, e);
                }
            }

            messages = message_finder(response);

            status = status_finder(response);

            // We can't depend on the first message being an error.
            var errors = messages.filter(function(m) {
                return m.level === "error";
            });
            if (errors && errors.length) {
                error = errors[0].content;
            } else if (!status) {
                error = LOCALE.maketext("No specific error was returned with the failed API call.");
            }

            var warnings = response.warnings && response.warnings.length ? response.warnings : null;

            // We include this here because the response from this function
            // should be agnostic as to the specific API version that we called.
            // If we don’t reduce the batch data now, then the caller will see
            // “data” as a list of structures that are specific to the API
            // version being called. Since the parsing logic is (appropriately)
            // housed in the IAPI module, we want to use that here.
            var is_batch = iapi_module.is_batch_response && iapi_module.is_batch_response(response);
            if (is_batch && Array.isArray(data)) {
                data = data.map( function(d) {
                    return base._parse_response_object(iapi_module, d);
                } );
            }

            return {
                parsedResponse: {
                    is_batch: is_batch,     // a convenience
                    status: status,
                    raw: response,
                    data: data,
                    meta: meta,
                    error: error,
                    messages: messages,
                    warnings: warnings,
                    messagesAreHtml: iapi_module.HTML_ESCAPES_MESSAGES,
                }
            };
        }


    };

    return base;
});
