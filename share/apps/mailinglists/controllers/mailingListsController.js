/*
# share/apps/mailinglists/src/views/mailingListsController    Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                        http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "app/services/mailingListsService"
    ],
    function(angular) {

        // Fetch the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /*
         * Creates a new MailingListsController
         * @class MailingListsController
         *
         * table view controller
         *
         */
        function MailingListsController($scope, MailingListService) {

            var _self = this;

            _self.model = MailingListService;

            _self.columnHeaders = [];

            /*
             * @method addColumn
             * builds column header object
             *
             * @param key {string} column key name (coorelates to api params)
             * @param name {string} Localized name used to label column
             */
            _self.addColumn = function(key, name) {
                _self.columnHeaders.push({
                    "key": key,
                    "name": name
                });
            };

            /*
             * @method getHeaders
             * get array of column headers
             *
             * @return {array} list of column objects {key:...,name:...}
             */
            _self.getHeaders = function() {
                return _self.columnHeaders;
            };

            /*
             * @method getLists
             * get array lists to display
             *
             * @return {array} list of MailingListItems
             */
            _self.getLists = function() {
                return _self.model.lists;
            };

            /*
             * add initial columns
             */
            _self.addColumn("list", LOCALE.maketext("List Name"));
            _self.addColumn("humandiskused", LOCALE.maketext("Usage"));
            _self.addColumn("accesstype", LOCALE.maketext("Access"));
            _self.addColumn("listadmin", LOCALE.maketext("Admin"));
            _self.addColumn("functions", LOCALE.maketext("Functions"));
        }

        MailingListsController.$inject = ["$scope", "mailingListsService"];
        app.controller("mailingListsController", MailingListsController);

    });
