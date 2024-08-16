/* global define: false */

define(
    [

        // Libraries
        "angular",

        // Application

        // CJT
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so its ready
    ],
    function(angular, LOCALE, API, APIREQUEST, APIDRIVER) {

        var app = angular.module("App");

        app.factory("FailedLoginService", ["$q", function($q) {

            var exports = {};

            function normalizeData(data) {

                // make the timeleft field an actual integer for sorting
                if (angular.isDefined(data.timeleft)) {
                    data.timeleft = parseInt(data.timeleft, 10);
                }

                // make the authservice the same as the service if there is no authservice specified
                if (angular.isDefined(data.service) && angular.isDefined(data.authservice)) {
                    if (data.authservice === "") {
                        data.authservice = data.service;
                    }
                }

                return data;
            }


            function convertResponseData(responseData) {
                var items = [];

                for (var i = 0, len = responseData.length; i < len; i++) {
                    items.push(normalizeData(responseData[i]));
                }

                return items;
            }

            exports.getBrutes = function(meta) {
                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_brutes");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.getExcessiveBrutes = function(meta) {

                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_excessive_brutes");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.getFailedLogins = function(meta) {
                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_failed_logins");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.getBlockedUsers = function(meta) {
                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_user_brutes");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            exports.clearHistory = function() {

                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "flush_cphulk_login_history");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.unBlockAddress = function(address) {

                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "flush_cphulk_login_history_for_ips");
                apiCall.addArgument("ip", address);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            deferred.resolve(results.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            return exports;
        }]);
    }
);
