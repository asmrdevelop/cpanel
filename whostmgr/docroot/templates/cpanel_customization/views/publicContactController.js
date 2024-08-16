/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/publicContactController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

( function() {
    "use strict";

    define(
        [
            "lodash",
            "angular",
            "cjt/util/locale",
            "uiBootstrap",
            "app/services/contactService",
            "cjt/decorators/growlAPIReporter",
            "app/services/savedService",
        ],
        function(_, angular, LOCALE) {

            /**
             * @typedef ContactModel
             * @property {string} name - the name of the company
             * @property {string} url - the url to reach the company at.
             */

            // Create the module
            var app = angular.module(
                "customize.views.publicContactController", [
                    "customize.services.contactService",
                    "customize.services.savedService",
                ]
            );
            app.value("PAGE", PAGE);

            var PAGEDATA = PAGE.data;

            // It might be nice for the form model to be saved in this
            // scope; that way we could restore the form state between
            // loads of this view. AngularJS, though, doesn’t seem to like
            // to create FormController objects that are $dirty from the
            // get-go. We’d have to hook into some sort of post-render event,
            // and AngularJS *really* seems to want to stay away from that
            // kind of logic.
            //
            var SAVED_PCDATA = angular.copy( PAGEDATA.public_contact );

            // Setup the controller
            var controller = app.controller(
                "publicContactController",
                [
                    "$scope",
                    "contactService",
                    "savedService",
                    "growl",
                    "growlMessages",
                    function($scope, contactService, savedService, growl, growlMessages) {
                        angular.extend(
                            $scope,
                            {
                                has_root: !!PAGEDATA.has_root,
                                pcdata: angular.copy(SAVED_PCDATA),

                                /**
                                 * Save the public contacts.
                                 *
                                 * @param {*} form
                                 * @returns
                                 */
                                doSubmit: function doSubmit(form) {
                                    var scope = this;

                                    growlMessages.destroyAllMessages();

                                    return contactService.setPublicContact(this.pcdata).then( function() {
                                        angular.extend(SAVED_PCDATA, scope.pcdata);
                                        form.$setPristine();
                                        savedService.update("public-contact", false);
                                        growl.success(LOCALE.maketext("The public can now view the information that you provided in this form."));
                                    } );
                                },

                                /**
                                 * Reset the form to it intial state.
                                 */
                                resetForm: function resetForm(form) {
                                    growlMessages.destroyAllMessages();

                                    angular.extend(this.pcdata, SAVED_PCDATA);
                                    form.$setPristine();
                                },
                            }
                        );

                        // Watch for changes
                        $scope.$watchGroup([ "pcdata.name", "pcdata.url" ], function() {
                            if (!$scope.public_contact_form) {
                                return;
                            }
                            savedService.update("public-contact", $scope.public_contact_form.$dirty);
                        }, true);

                    },
                ]
            );

            return controller;
        }
    );

}());
