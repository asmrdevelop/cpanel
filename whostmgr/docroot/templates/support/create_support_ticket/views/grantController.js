/*
 * views/grantController.js                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "cjt/util/locale",
    "cjt/directives/alert"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("grantController", [
        "$scope",
        "pageState",
        "wizardApi",
        function(
            $scope,
            pageState,
            wizardApi
        ) {

            if (!wizardApi.verifyStep(/grant$/)) {
                return;
            }

            // Load the grant from any previous trips through the
            // wizard or else make it true so we encourage people
            // to grant.
            $scope.allowGrant = !angular.isUndefined(pageState.data.grant.allow) ?
                pageState.data.grant.allow :
                true;

            // Only true while the grant checkbox hasn't been touched
            $scope.initGrant = true;

            /**
             * Toggles the state of the user's choice to allow access to his or her server
             * and sets the initGrant flag to false.
             *
             * @method toggleAllow
             */
            $scope.toggleAllow = function() {
                $scope.initGrant = false;
                $scope.allowGrant = !$scope.allowGrant;
            };

            /**
             * Stops propagation for a particular event.
             *
             * @method stopPropagation
             * @param  {Event} e   An event object.
             */
            $scope.stopPropagation = function(e) {
                $scope.initGrant = false;
                e.stopPropagation();
            };

            /**
             * Navigate to the previous view.
             *
             * @name previous
             * @scope
             */
            var previous = function() {
                if (pageState.tos.accepted) {
                    wizardApi.reset();
                    return false;
                } else {
                    wizardApi.loadView("/tos");
                    return true;
                }
            };

            /**
             * Navigate to the next view.
             *
             * @name next
             * @scope
             */
            var next = function() {
                pageState.data.grant.allow = $scope.allowGrant;
                wizardApi.loadView("/processing");
                return true;
            };

            wizardApi.configureStep({
                nextFn: next,
                previousFn: previous
            });

        }
    ]);
});

// maketext('Fake maketext call to ensure this file remains in .js_files_in_repo_with_mt_calls')
