/*
# share/apps/mailinglists/src/views/mainController          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/* TABLE ControllerCode */

define(
    [
        "angular",
        "app/services/mailingListsService",
        "cjt/directives/alertList",
        "cjt/filters/qaSafeIDFilter",
        "cjt/decorators/paginationDecorator"
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
         * Creates a new MainController
         * @class MainController
         *
         * serves the purpose of the table controller
         * and handles the inital loading of the lists
         *
         */
        function MainController($scope, MailingListService, spinnerAPI) {

            var _self = this;

            _self.model = MailingListService;
            _self.spinner = spinnerAPI;

            $scope.totalItems = _self.model.totalResults;
            $scope.currentPage = _self.model.page;

            /*
             * watches the loading param on the MalingListService
             * and shows or hides the spinner accordingly
             */
            $scope.$watch(function() {
                return _self.model.loading;
            }, function() {
                if (_self.model.loading) {
                    _self.spinner.start();
                } else {
                    _self.spinner.stop();
                }
            });

            /*
             * @method startSearch
             * wrapper function to start the search based on filter
             *
             */
            _self.startSearch = function() {
                _self.model.page = 0;
                _self.model.getLists();
            };

            /*
             * @method clearSearch
             * clear the filterValue and reload lists
             *
             */
            _self.clearSearch = function() {
                _self.model.filterValue = "";
                _self.model.selectPage(0);
            };

            $scope.$watch(function() {
                return _self.model.pageSize;
            }, function(newValue, oldValue) {

                if (newValue !== oldValue) {
                    _self.model.getLists();
                }
            });

            $scope.$watch(function() {
                return _self.model.filterValue;
            }, function(newValue, oldValue) {
                if (newValue !== "") {
                    _self.startSearch();
                } else if (newValue !== oldValue) {
                    _self.clearSearch();
                }
            });

        }

        MainController.$inject = ["$scope", "mailingListsService", "spinnerAPI"];
        app.controller("mainController", MainController);

    });
