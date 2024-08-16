/*
 * templates/multiphp_manager/views/phpHandlers.js       Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/configService"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "phpHandlers",
            ["$scope", "$location", "$routeParams", "$timeout", "$filter", "configService", "spinnerAPI", "alertService", "growl", "growlMessages", "$anchorScroll", "PAGE",
                function($scope, $location, $routeParams, $timeout, $filter, configService, spinnerAPI, alertService, growl, growlMessages, $anchorScroll, PAGE) {

                // Setup data structures for the view
                    $scope.loadingVersionsList = false;
                    $scope.phpVersionsEmpty = true;
                    $scope.meta = {

                    // Sort settings
                        sortReverse: false,
                        sortBy: "version",
                        sortDirection: "asc"
                    };

                    var orderBy = $filter("orderBy");

                    $scope.sortList = function() {

                    // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            $scope.phpVersionHandlerList = orderBy($scope.phpVersionHandlerList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }
                    };

                    $scope.editPhpHandler = function(itemToEdit) {

                    // set that record's editView = true;
                        itemToEdit.editView = true;

                    };

                    var clearConflictView = function(item) {
                        item.conflicts = [];
                        item.showAlert = false;
                    };

                    var applyListToTable = function(resultList) {
                        var versionList = resultList.items;

                        $scope.phpVersionHandlerList = versionList.map(function(item) {
                            item.editView = false;
                            item.conflicts = [];    // Records all the conflicts that happen when a handler is changed.
                            item.showAlert = false; // Used when conflicts/warnings need to be shown
                            item.originalHandler = item.current_handler;  // Used to decide when to show/hide warning.
                            return item;
                        });
                    };

                    $scope.cancelHandlerEdit = function(item) {
                        item.editView = false;
                        item.current_handler = item.originalHandler;
                        clearConflictView(item);
                    };

                    /**
                 * Fetch the list of PHP versions with their associated handlers.
                 * @return {Promise} Promise that will result in the list being loaded with the PHP versions with handlers.
                 */
                    $scope.fetchVersionHandlerList = function() {
                        $scope.loadingVersionsList = true;
                        return configService
                            .fetchVersionHandlerList()
                            .then(function(results) {
                                applyListToTable(results);
                                $scope.lsApiInstalled = _.includes(_.uniq(
                                    _.flatten(
                                        _.map($scope.phpVersionHandlerList, "available_handlers")
                                    )
                                ), "lsapi");
                            }, function(error) {

                            // failure
                                growl.error(error);
                            })
                            .then(function() {
                                $scope.loadingVersionsList = false;
                            });
                    };

                    // Apply the new PHP version setting of a selected user
                    $scope.applyVersionHandler = function(item) {
                        growlMessages.destroyAllMessages();
                        clearConflictView(item);
                        return configService.applyVersionHandler(item.version, item.current_handler)
                            .then(
                                function(success) {
                                    if (success) {
                                        growl.success(LOCALE.maketext("Successfully applied the “[_1]” [asis,PHP] handler to the “[_2]” package.", item.current_handler, item.version));
                                        item.originalHandler = item.current_handler;
                                        item.editView = false;
                                    }
                                })
                            .catch(function(error) {
                                growl.error(_.escape(error));
                            });
                    };

                    $scope.warnUser = function(versionHandler, originalHandler) {
                        if ( versionHandler.current_handler !== originalHandler ) {
                            versionHandler.showAlert = true;
                        } else {
                            versionHandler.showAlert = false;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        growlMessages.destroyAllMessages();
                        $scope.fetchVersionHandlerList();
                        $scope.clData = PAGE.cl_data;
                        $scope.clBannerText = LOCALE.maketext("To utilize the [asis,LSAPI] handler’s full functionality and performance benefits, upgrade your system to [asis,CloudLinux]. To learn more about this feature, please read [output,url,_1,CloudLinux - Mod_lsapi Feature,target,_2].", "https://go.cpanel.net/CL-lsapi", "blank");
                    });
                }
            ]);

        return controller;
    }
);
