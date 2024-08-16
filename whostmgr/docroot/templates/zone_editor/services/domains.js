/*
# zone_editor/services/domains.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/util/httpStatus",
        "cjt/core",
        "cjt/io/whm-v1",
    ],
    function(angular, _, LOCALE, API, APIREQUEST, HTTP_STATUS, CJT) {

        "use strict";

        var SERVICE_NAME = "Domains";
        var MODULE_NAMESPACE = "whm.zoneEditor.services.domains";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = function($q, defaultInfo) {

            var store = {};

            store.domains = [];

            store.fetch = function() {

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "listzones");

                return store._promise(apiCall)
                    .then(function(response) {
                        response = response.parsedResponse;

                        if (response.status) {
                            if (response.data !== null) {
                                store.domains = response.data.map(function(domain) {
                                    return {
                                        domain: domain.domain
                                    };
                                });
                            } else {
                                store.domains = [];
                            }

                            return $q.resolve(store.domains);
                        } else {
                            return $q.reject(response);
                        }
                    })
                    .catch(store._parseAPIFailure);
            };

            store.init = function() {
                store.domains = defaultInfo.domains.map(function(domain) {
                    return {
                        domain: domain
                    };
                });
            };

            store._promise = function(apiCall) {
                return $q.when(API.promise(apiCall.getRunArguments()));
            };

            store._parseAPIFailure = function(response) {
                if (!response.status) {
                    return $q.reject(response.error);
                }
                return $q.reject(store.request_failure_message(response.status));
            };

            /**
             * Generates the error text for when an API request fails.
             *
             * @method request_failure_message
             * @param  {Number|String} status   A relevant status code.
             * @return {String}                 The text to be presented to the user.
             */
            store.request_failure_message = function(status) {
                var message = LOCALE.maketext("The API request failed with the following error: [_1] - [_2].", status, HTTP_STATUS.convertHttpStatusToReadable(status));
                if (status === 401 || status === 403) {
                    message += " " + LOCALE.maketext("Your session may have expired or you logged out of the system. [output,url,_1,Login] again to continue.", CJT.getLoginPath());
                }

                return message;
            };

            store.init();

            return store;
        };

        app.factory(SERVICE_NAME, ["$q", "defaultInfo", SERVICE_FACTORY]);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);
