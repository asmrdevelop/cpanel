/**
 * cjt/decorators/$httpDecorator.js                Copyright(c) 2016 cPanel, Inc.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
    ],
    function(angular) {

        // Retrieve the module
        var module = angular.module("cjt2.decorators.$http", []);

        module.run(["$http", function($http) {
            $http.postAsForm = function(url, data, config) {

                if (typeof url !== "string") {
                    throw new TypeError("Developer Error: $http.postAsForm requires a \"url\" argument.");
                }

                if (!angular.isObject(config)) {
                    config = {};
                }

                if (data) {
                    if ("data" in config) {
                        throw new ReferenceError("Developer Error: $http.postAsForm does not accept a \"config.data\" key when there is a \"data\" argument.");
                    }
                    config.data = data;
                }

                angular.merge(config, {
                    method: "POST",
                    url: url,
                    transformRequest: function(args) {
                        var uriEncoded = [];
                        angular.forEach(args, function(val, key) {
                            uriEncoded.push(encodeURIComponent(key) + "=" + encodeURIComponent(val));
                        });
                        return uriEncoded.join("&");
                    },
                    headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8" }
                });

                return $http(config);
            };
        }]);
    }
);
