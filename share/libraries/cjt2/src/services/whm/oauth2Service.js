/*
 * cjt/services/whm/oauth2Service.js               Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "jquery",
    "cjt/core"
], function(
        angular,
        $,
        CJT_CORE
    ) {

    var module = angular.module("cjt2.services.whm.oauth2", []);

    module.factory("oauth2Service", [
        "$window",
        "$rootScope",
        "$httpParamSerializer",
        function(
            $window,
            $rootScope,
            $httpParamSerializer
        ) {

            /**
             * Ensures the presence of any required parameters in an OAuth2 params object.
             * Throws if any of them are missing.
             *
             * @method _checkParams
             * @private
             * @param  {Object} params   An OAuth2 params object.
             * @return {Boolean}         True if it has all of the required parameters.
             */
            function _checkParams(params) {
                var missingProps = [];
                ["client_id", "redirect_uri", "response_type"].forEach(function(prop) {
                    if ( !angular.isDefined( params[prop]) || !params[prop].length ) {
                        missingProps.push(prop);
                    }
                });

                if (missingProps.length) {
                    throw new ReferenceError("The OAuth2 params object must include the following properties: " + missingProps.join(","));
                }

                if (params.redirect_uri.indexOf("/") !== 0) {
                    throw new Error("The redirect_uri parameter value must be an absolute path without the domain, port, or protocol.");
                }

                if (params.scope && !angular.isArray(params.scope)) {
                    throw new TypeError("The scope parameter value must be an array of requested scopes.");
                }

                return true;
            }

            /**
             * Prepares the parameters model for serialization.
             *
             * @method _prepareParams
             * @private
             * @param  {Object} params   An object containing parameters for an OAuth2 URL.
             * @return {Object}          The transformed object that is ready for serialization.
             */
            function _prepareParams(params) {
                var preparedParams = angular.copy(params);

                // Append our server's base path to the absolute path of the redirect_uri
                preparedParams.redirect_uri = CJT_CORE.getRootPath() + preparedParams.redirect_uri;

                // Scopes should be listed in a comma separated string
                if (preparedParams.scope && preparedParams.scope.length) {
                    preparedParams.scope = preparedParams.scope.join(",");
                }

                if (preparedParams.email) {
                    var emails = preparedParams.email.split(/[,]/);

                    // Just use the first one by default
                    preparedParams.email = emails[0];
                }

                return preparedParams;
            }

            return {

                /**
                 * This method sets the endpoint and query parameters for later use.
                 *
                 * @method initialize
                 * @param {String} endpoint   The URL for the authentication endpoint.
                 * @param {Object} params     An object that will be transformed into the query string of the OAuth2 URL.
                 */
                initialize: function(endpoint, params) {
                    if (!endpoint) {
                        throw new ReferenceError("An OAuth2 endpoint is required to initialize the OAuth2 service.");
                    }

                    if ( _checkParams(params) ) {
                        this.endpoint = endpoint;
                        this.params = params;
                        return this;
                    }
                },

                /**
                 * Combine all the pieces to create the full authentication URI
                 *
                 * @method getAuthUri
                 * @return {String}   The authentication URL including all query parameters
                 */
                getAuthUri: function() {
                    return ( encodeURI(this.endpoint) + "?" + $httpParamSerializer( _prepareParams(this.params) ) );
                },

                /**
                 * Sets a callback to be executed after successful authorization and redirect. This callback is
                 * called from /unprotected/oauth2callback.html after the redirect.
                 *
                 * @method setCallback
                 * @param {Function} callback   The callback function to run.
                 */
                setCallback: function(callback) {
                    $window.oauth2Callback = function(queryString) {
                        callback(queryString);
                        $rootScope.$apply(); // This is happening outside of Angular's view, so we have to trigger it manually
                        this.unsetCallback();
                    }.bind(this);
                },

                /**
                 * Remove a callback that was previously set.
                 *
                 * @method unsetCallback
                 */
                unsetCallback: function() {
                    delete $window.oauth2Callback;
                }
            };
        }
    ]);
});
