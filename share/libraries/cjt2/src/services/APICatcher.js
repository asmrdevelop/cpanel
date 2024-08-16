/*
# cjt/services/APICatcher.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define([
    "angular",
    "lodash",
    "cjt/util/locale",
    "cjt/services/onBeforeUnload",
    "cjt/services/APIService",
    "cjt/services/APIFailures",
],
function(angular, _, LOCALE) {
    "use strict";

    /* A service to simplify API interactions by providing default
         * error handling logic. Use this for situations where you’re not
         * all that concerned with how the API reports failure, as long
         * as it reports it *somehow*.
         *
         * Example usage:
         *
         *      var promise = APICatcher.promise( apiCall );
         *
         * The returned promise has a “catch”er registered that will
         * report the failure to the APIFailures service; anything that
         * is registered with that service will then receive a notification.
         * The “growlAPIReporter” decorator includes such registration and
         * is the intended “complement” module for APICatcher; however,
         * if you want some other means of catching unreported failures,
         * it’s as simple as creating a new module that registers with
         * APIFailures.
         */

    var module = angular.module("cjt2.services.apicatcher", [
        "cjt2.services.api",
        "cjt2.services.apifailures",
        "cjt2.services.onBeforeUnload"
    ]);

    // A function to iterate through a batch result and collect
    // error strings.
    function _collectFailureStrings(result, strings) {
        if (!strings) {
            strings = [];
        }

        if (result.is_batch) {
            result.data.forEach( function(d) {
                _collectFailureStrings(d, strings);
            } );
        } else if (result.error) {
            strings.push(result.error);
        }

        return strings;
    }

    module.factory("APICatcher", ["APIService", "APIFailures", "onBeforeUnload", "$q", "$log", function(APIService, APIFailures, onBeforeUnload, $q, $log) {

        var errorPhraseToSuppress;

        // ----------------------------------------------------------------------
        // APIService doesn’t expose the actual reported HTTP error status.
        // So we subclass APIService and install a custom “fail” handler that
        // checks the HTTP status and, if that status indicates that we should
        // suppress the error message, designates that phrase as “the phrase
        // to suppress”.
        //
        // It’s ugly, but the alternative would be to return an object, which
        // would break all handlers of the promise’s rejection case.
        //
        function APIServiceForCatcher() {
            return APIService.apply(this, arguments);
        }
        APIServiceForCatcher.prototype = Object.create(APIService.prototype);

        var baseHttpFailHandler = APIService.prototype.presetDefaultHandlers.fail;
        var customHttpFailHandler = function(xhr, deferred) {
            var mockDeferred = $q.defer();
            mockDeferred.promise.then(
                function(val) {
                    throw "Improper APICatcher success: " + val;
                },
                function(val) {

                    // Suppress display of the error if the failure
                    // is reported as HTTP status “0”.
                    // cf. https://yui.github.io/yui2/docs/yui_2.9.0_full/connection/index.html#failure
                    var shouldSuppress = onBeforeUnload.windowIsUnloading();
                    shouldSuppress = shouldSuppress && (xhr.status === 0);

                    if (shouldSuppress) {
                        errorPhraseToSuppress = val;
                    }

                    deferred.reject(val);
                }
            );

            baseHttpFailHandler.call(this, xhr, mockDeferred);
        };

        var presetDefaultHandlers = _.assign(
            {},
            APIService.prototype.presetDefaultHandlers
        );
        presetDefaultHandlers.fail = customHttpFailHandler;

        _.assign(
            APIServiceForCatcher.prototype,
            {
                presetDefaultHandlers: presetDefaultHandlers,
            }
        );

        // The tests mock APIService.promise, so let’s call into
        // that function rather than just assigning the function as
        // APIServiceForCatcher.promise.
        APIServiceForCatcher.promise = function _promise() {
            return APIService.promise.apply(this, arguments);
        };

        // ----------------------------------------------------------------------

        var MAX_MESSAGES_DISPLAYED = 6;

        function _processResultForMessages(result) {
            var messages = [];
            if (typeof result !== "object") {

                // Assume it's a string
                if (result !== errorPhraseToSuppress) {
                    messages.push({
                        type: "danger",
                        content: result,
                    });
                }
            } else {

                // Response Object
                if (result.error) {
                    _collectFailureStrings(result).forEach( function(str) {
                        messages.push({
                            type: "danger",
                            content: str,
                        });
                    } );
                }

                if (result.warnings && result.warnings.length) {
                    messages.push.apply(
                        messages,
                        result.warnings.map( function(w) {
                            return {
                                type: "warning",
                                content: w,
                            };
                        } )
                    );
                }
            }

            // emit warnings and errors
            if (messages.length) {
                var displayed = messages.slice(0, MAX_MESSAGES_DISPLAYED);

                var notDisplayed = messages.slice(MAX_MESSAGES_DISPLAYED);
                if (notDisplayed.length) {
                    var translateToLog = {
                        warning: "warn",
                        danger: "error",
                    };

                    notDisplayed.forEach( function(msg) {
                        $log[ translateToLog[msg.type] ](msg.content);
                    } );

                    displayed.push({
                        type: "warning",
                        content: "<em>" + LOCALE.maketext("The system suppressed [quant,_1,additional message,additional messages]. Check your browser console for the suppressed [numerate,_1,message,messages].", notDisplayed.length) + "</em>"
                    });
                }

                // UAPI and API2 have already escaped their errors
                // by this point. WHM v1 hasn’t.
                if (!result.messagesAreHtml) {
                    displayed.forEach( function(msg) {
                        msg.content = _.escape(msg.content);
                    } );
                }

                APIFailures.emit(displayed);
            }

            return result;
        }

        function _promiseOrCatch(apiCall) {
            var promise = APIServiceForCatcher.promise(apiCall);
            promise.then(_processResultForMessages, _processResultForMessages);
            return promise;
        }

        return {
            promise: _promiseOrCatch,
        };
    }] );
}
);
