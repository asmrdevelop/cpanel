/*
# base/sharedjs/angular/oauth2.js                        Copyright(c) 2018, Inc.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Angular application that handles client side of OAuth2 mechanism
 *
 * @module OAuth2App
 *
 */
var OAuth2App = angular.module( "OAuth2App", [] );

/**
 * Controller that handles the OAuth2 client popout window
 *
 * @method Authorize controller
 * @param {Object} $scope The Angular scope variable
 * @param {Object} $http The Angular HTTP request object
 */
OAuth2App.controller( "OAuth2Landing", [ "$scope", "$http", "$window",
    function($scope, $http, $window) {
        "use strict";

        // initial states
        $scope.oauth2_endpoint = PAGE.oauth2_endpoint;
        $scope.oauth2_config   = PAGE.oauth2_config;
        $scope.isProcessing    = false;

        /**
         * Helper method that prepends host to the partial redirect uri
         *
         * @method buildRedirectURI
         * @param {String} uri The partial uri to be used in the construction of the redirect
         */
        $scope.buildRedirectURI = function(uri) {
            return location.protocol + "//" + location.hostname + ":" + location.port + uri;
        };

        // construct the redirect_uri for cross browser compatibility
        $scope.oauth2_config.redirect_uri = $scope.buildRedirectURI($scope.oauth2_config.redirect_uri);

        /**
         * Kicks the OAuth2 validation flow off
         */
        $scope.login = function() {
            var popupOptions = {
                name: "OAuth2Window",
                openParams: {
                    autoCenter: true,
                    height: 415,
                    width: 450
                }
            };

            /**
             * Converts hash into key/value pairs for the window function
             *
             * - Object - hash
             *
             * @returns Object.<(string|boolean)>
             */
            var formatPopupOptions = function(options) {
                var pairs = [];
                angular.forEach(options, function(value, key) {
                    if (value || value === 0) {
                        value = value === true ? "yes" : value;
                        pairs.push(key + "=" + value);
                    }
                });
                return pairs.join(",");
            };

            if ($scope.oauth2_config && $scope.oauth2_config.email) {
                var emails = $scope.oauth2_config.email.split(/[,]/);

                // Just use the first one by default
                $scope.oauth2_config.email = emails[0];
            }

            var url = encodeURI($scope.oauth2_endpoint) + "?" + $.param($scope.oauth2_config);

            $window.open( url, popupOptions.name, formatPopupOptions(popupOptions.openParams) );
        };
    }
]);
