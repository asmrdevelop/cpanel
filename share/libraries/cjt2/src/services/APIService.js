/*
# cjt/services/APIService.js                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// ----------------------------------------------------------------------
// HEY YOU!! Looking for quick-and-simple?
//
// var promise = APIService.promise( apiCall );
//
// ...where apiCall is a “request” object, in the mold of uapi-request.js.
// ----------------------------------------------------------------------

/**
 * This module generates an angular.js service that can be used as a
 * subclass for your custom services.
 *
 * @module cjt/services/APIService
 */

define([
    "angular",
    "cjt/core",
    "cjt/util/locale",
    "cjt/io/api",
    "cjt/util/httpStatus"
],
function(angular, CJT, LOCALE, API, HTTP_STATUS) {

    "use strict";

    var module = angular.module("cjt2.services.api", []);

    function reduceResponse(response) {
        var resp = response.parsedResponse;

        if (resp && resp.is_batch) {
            for (var i = 0; i < resp.data.length; i++) {
                resp.data[i] = reduceResponse( resp.data[i] );
            }
        }

        return resp;
    }

    return module.factory("APIService", ["$q", function($q) {

        /**
         * Test if the argument is defined and is a function.
         *
         * @private
         * @method _isFunc
         * @param  {Any}  func
         * @return {Boolean}   true if defined and is a function, false otherwise.
         */
        function _isFunc(func) {
            return func && angular.isFunction(func);
        }

        /**
         * This is an Angular wrapper for jquery-based XHR request promise.
         *
         * @private
         * @construtor
         * @param {RunArguments} apiCall Contains a valid API request object.
         * @param {Object} [handlers] Optional. Contains any overridden handlers. See defaultHandlers below for candidate names.
         * @param {Deferred} [deferred] Optional. Deferred passed from outer context. Created if not passed.
         */
        function AngularAPICall(apiCall, handlers, deferred) {
            this.handlers = handlers;
            this.deferred = deferred = deferred || $q.defer();

            this.jqXHR = API.promise(apiCall.getRunArguments())
                .done(function(response) {
                    handlers.done(response, deferred);
                })
                .fail(function(xhr, textStatus) {
                    if (textStatus === "abort") {
                        handlers.abort(xhr, deferred);
                    } else {
                        handlers.fail(xhr, deferred);
                    }
                });

            // Since API calls from JS are just HTTP underneath, we can
            // expose a means of canceling them. Rather than being called
            // something like .cancel(), this has a “namespaced” name
            // in order to avoid unintended interactions with any potential
            // changes to the underlying deferred/promise stuff.
            deferred.promise.cancelCpCall = this.jqXHR.abort.bind(this.jqXHR);
        }

        /**
          * Constructor for an APIService. Sets up the instance's default handler methods.
          *
          * @class
          * @exports module:cjt/io/APIService:APIService
          * @param  {Object} instanceDefaultHandlers   If you would like to override any of the default handlers
          *                                            for the instance, pass them here. Otherwise, the preset
          *                                            defaults will be used.
          */
        function APIService(instanceDefaultHandlers) {
            this.defaultHandlers = angular.extend({}, this.presetDefaultHandlers, instanceDefaultHandlers || {});
        }

        APIService.prototype = {

            /**
             * Wrap an api call with application standard done and fail code. The caller can override behavior
             * via the overrides property which is an object containing the specific parts to override. The
             * overrides argument will only pertain to this single API instance. Overrides in the instance
             * defaults are next in the hierarchy, followed by the preset defaults for the base API service.
             *
             * @method deferred
             * @instance
             * @param  {RunArguments} apiCall    An api request helper object containing arguments, filters, etc.
             * @param  {Object}   overrides  An object of overrides. See getCallHandlers documentation.
             *   @param {Function} overrides.done                  Replaces the default jqXHR done handling.
             *   @param {Function} overrides.fail                  Replaces the default jqXHR fail handling.
             *   @param {Function} overrides.apiSuccess            Replaces standard api success handling.
             *                                                     Called when not overridding done.
             *   @param {Function} overrides.apiFailure            Replaces standard api failure handling.
             *                                                     Called when not overridding done.
             *   @param {Function} overrides.transformApiSuccess   Transforms the response on success. If not provided,
             *                                                     the default behavior is to return the whole response.
             *                                                     Called when not overriding apiSuccess.
             *   @param {Function} overrides.transformApiFailure   Transforms the response on failure. If not provided,
             *                                                     default behavior is to return the whole error.
             *                                                     Called when not overriding apiFailure.
             * @param  {Deferred} [deferred] Optional deferred created with $q.defer(). If not passed one will be created internally.
             * @return {Deferred}            Deferred wrapping the api call.
             */
            deferred: function(apiCall, overrides, deferred) {
                var handlers = {};

                if (overrides) {

                    // Iterate over the defaultHandlers and see if there are overrides with the same key
                    angular.forEach(this.defaultHandlers, function(defaultHandler, handlerName) {
                        if (_isFunc(overrides[handlerName])) {

                            // If a context is provided, bind the handler to that context
                            handlers[handlerName] = (angular.isObject(overrides.context) || angular.isFunction(overrides.context)) ?
                                overrides[handlerName].bind(overrides.context) : overrides[handlerName];
                        } else {
                            handlers[handlerName] = defaultHandler;
                        }
                    }, this);
                } else {
                    handlers = this.defaultHandlers;
                }

                return this.sendRequest(apiCall, handlers, deferred);
            },

            /**
             * Generates a new Angular wrapper instance for the API call. This is a separate method
             * to present an easy way to mock this step for testing.
             *
             * @method sendRequest
             * @instance
             * @param  {RunArguments} apiCall    See deferred method documentation.
             * @param  {Object}       handlers   See deferred method documentation.
             * @param  {Deferred}     deferred   See deferred method documentation.
             * @return {Deferred}                A $q wrapped jqXHR promise.
             */
            sendRequest: function(apiCall, handlers, deferred) {
                return new AngularAPICall(apiCall, handlers, deferred).deferred;
            },

            /**
             * Since this class is meant to be sub-classed per service, the defaultHandlers are kept
             * here so that each service can conveniently overwrite them in one place.
             *
             * The handlers all run within the context of the handlers object by default, so if you
             * override them and need another context, make sure to use Function.bind or use some
             * other mechanism to keep access to your scope.
             */
            presetDefaultHandlers: {
                done: function(response, deferred) {
                    var toCaller = reduceResponse(response);

                    if (toCaller && toCaller.status) {
                        this.apiSuccess(toCaller, deferred);
                    } else {
                        this.apiFailure(toCaller, deferred);
                    }
                },

                fail: function(xhr, deferred) {
                    deferred.reject(_requestFailureText(xhr));
                },

                abort: function(xhr, deferred) {

                    // Intentionally a no-op. Override this if you want to reject the promise.
                },

                apiSuccess: function(response, deferred) {
                    deferred.resolve(this.transformAPISuccess(response));
                },

                apiFailure: function(response, deferred) {
                    deferred.reject(this.transformAPIFailure(response));
                },

                transformAPISuccess: function(response) {
                    return response;
                },

                transformAPIFailure: function(response) {
                    return response.error;
                }
            }
        };

        /**
         * Generates the error text for when an API request fails.
         *
         * TODO: This should really only be called when the API doesn’t
         * return any useful information other than the HTTP status codes.
         * Currently it disregards useful information in the API response,
         * e.g., the “reason” given in the JSON response from WHM API v1.
         *
         * @method _requestFailureText
         * @private
         * @param  {Number|String} status   A relevant status code.
         * @return {String}                 The text to be presented to the user.
         */
        function _requestFailureText(xhr) {
            var status = xhr.status;
            var message = LOCALE.maketext("The API request failed with the following error: [_1] - [_2].", status, HTTP_STATUS.convertHttpStatusToReadable(status));
            if (status === 401 || status === 403) {
                message += " " + LOCALE.maketext("Your session may have expired or you logged out of the system. [output,url,_1,Login] again to continue.", CJT.getLoginPath());
            }

            // These messages come from cpsrvd itself, not from the the API.
            // (API messages don’t produce HTTP-level errors.)
            try {
                var parsed = JSON.parse(xhr.responseText);
                if (parsed.error) {
                    message += ": " + parsed.error;
                }
                if (parsed.statusmsg) {
                    message += ": " + parsed.statusmsg;
                }
            } catch (e) {
                if (xhr.responseText) {
                    message += ": " + xhr.responseText.substr(0, 1024);

                    // not json so we show the first 1024
                    // chars of the message
                }
            }
            return message;
        }

        APIService.AngularAPICall = AngularAPICall;

        var keepFailureObject = { transformAPIFailure: Object };

        /**
         * Starts an async request with the given request
         *
         * @static
         * @param  {RunArguments} apiCall
         * @return {Promise}
         */
        APIService.promise = function promise(apiCall) {

            // The use of “this” as the constructor allows
            // this static method to be assigned to subclass constructors,
            // and all will work as it should.
            return (new this(keepFailureObject)).deferred(apiCall).promise;
        };

        return APIService;
    }]);
}
);
