/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/beforeUnloadService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
],
function(angular) {
    "use strict";

    /*
     * This service is used to send events when the window
     * onbeforeunload and onunload event happen.
     *
     * The service will broadcast the following events:
     *
     * onBeforeUnload - application code can register for this event on the scope. This
     * event can be used to prevent the unload using the `event.preventDefault()` technique.
     * Note, not all browsers will show the unload popup. Some also wont show it unless the
     * user has interacted with the form. Some browser will not use the custom message.
     *
     * onUnload - application code can register for this event on the scope. It can be used
     * to clean up any resources or cancel outstanding remote calls. You can not cancel the
     * unload from this event.
     */

    angular.module("customize.services.beforeUnloadService", [])
        .factory("beforeUnload", [ "$rootScope", "$window", function($rootScope, $window) {

            /**
             * Handler for the browser onbeforeunload event.
             *
             * @param {Event} e
             * @returns {string|undefined} - A message to show the user when deciding if they want to cancel the unload.
             */

            $rootScope.doBeforeUnload = function(e) {
                var config = {};

                /**
                 * @typedef {Config}
                 * @property {string} prompt - the propt to tell the user.
                 */
                var event = $rootScope.$broadcast("onBeforeUnload", config);
                if (event.defaultPrevented) {
                    e.preventDefault();

                    // Note: Some browsers will not show this message, but instead have their own.
                    e.returnValue = config.prompt || ""; // For some Chrome browsers
                    return config.prompt;
                } else {
                    delete e["returnValue"]; // For some Chrome browsers
                    return false;
                }
            };


            /**
             * Handler for the browser unload event
             */
            $rootScope.doUnload = function() {
                $rootScope.$broadcast("onUnload");
            };

            $window.addEventListener("beforeunload", $rootScope.doBeforeUnload);
            $window.addEventListener("onunload", $rootScope.doUnload);

            return {};
        } ] )
        .run(["beforeUnload", function(beforeUnload) {

        // Must invoke the service at least once
        } ] );
});
