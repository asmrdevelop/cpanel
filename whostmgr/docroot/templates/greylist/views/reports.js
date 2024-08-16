/*
# templates/greylist/views/reports.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                                  All rights reserved.
# copyright@cpanel.net                                                http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/parse",
        "cjt/util/locale",
        "moment",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/toggleSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/decorators/growlDecorator",
        "app/services/GreylistDataSource",
        "app/filters/relativeTimeFilter"
    ], function(angular, $, _, PARSE, LOCALE, moment) {

        var ipV6Test = /:/;

        // set the initial locale
        var currentLocale = PAGE.current_locale;
        moment.locale(currentLocale);

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "reportsController",
            ["$scope", "GreylistDataSource", "growl", "growlMessages", "PAGE",
                function($scope, GreylistDataSource, growl, growlMessages, PAGE) {

                    $scope.greylistEntries = [];
                    $scope.dropdownAddresses = [];

                    $scope.loadingPageData = false;
                    $scope.updatingPageData = false;
                    $scope.meta = {
                        filterBy: "*",
                        filterCompare: "contains",
                        filterValue: "",
                        sortDirection: "desc",
                        sortBy: "create_time",
                        sortType: "",
                        pageNumber: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100],
                        maxPages: 0,
                        totalRows: 0
                    };

                    function convertIpToSlash16Range(ipToConvert) {
                        var ipSegments = ipToConvert.split(".");

                        return ipSegments[0] + "." + ipSegments[1] + ".0.0/16";
                    }

                    function convertIpToSlash24Range(ipToConvert) {
                        var ipSegments = ipToConvert.split(".");

                        return ipSegments[0] + "." + ipSegments[1] + "." + ipSegments[2] + ".0/24";
                    }

                    $scope.search = function() {
                        return $scope.fetch({ "isUpdate": true });
                    };

                    $scope.sortList = function() {
                        return $scope.fetch({ "isUpdate": true });
                    };

                    $scope.changePageSize = function() {
                        return $scope.fetch({ "isUpdate": true });
                    };

                    $scope.fetchPage = function(page) {

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.currentPage = page;
                        }
                        return $scope.fetch({ "isUpdate": true });
                    };

                    $scope.toggleIPAddressDropdown = function(open, address) {
                        if (open) {
                            if (ipV6Test.test(address)) {
                                $scope.dropdownAddresses = [
                                    address + "/128",
                                    address + "/64"
                                ];
                            } else {
                                $scope.dropdownAddresses = [
                                    address,
                                    convertIpToSlash24Range(address),
                                    convertIpToSlash16Range(address)
                                ];
                            }
                        }
                    };

                    $scope.fetch = function(options) {
                        if (options && options.isUpdate) {
                            $scope.updatingPageData = true;
                        } else {
                            $scope.loadingPageData = true;
                            $scope.greylistEntries = [];
                        }

                        return GreylistDataSource.fetchDeferredEntries($scope.meta)
                            .then(function(data) {
                                $scope.greylistEntries = data.list;
                                $scope.timezone = data.timezone;
                                $scope.utcOffset = data.utc_offset;

                                $scope.meta.pageSize = parseInt(data.meta.paginate.page_size, 10);
                                $scope.meta.totalRows = data.meta.paginate.total_records;
                                $scope.meta.pageNumber = data.meta.paginate.current_page;
                                $scope.meta.pageNumberStart = data.meta.paginate.current_record;

                                if ($scope.meta.totalRows === 0) {
                                    $scope.meta.pageNumberStart = 0;
                                }

                                $scope.meta.pageNumberEnd = ($scope.meta.pageNumber * $scope.meta.pageSize);


                                if ($scope.meta.pageNumberEnd > $scope.meta.totalRows) {
                                    $scope.meta.pageNumberEnd = $scope.meta.totalRows;
                                }

                            }, function(error) {
                                growl.error(error);
                            }
                            )
                            .finally(function() {
                                $scope.loadingPageData = false;
                                $scope.updatingPageData = false;
                            });
                    };

                    $scope.addToTrustedHost = function(ipOrRange) {
                        if (!ipOrRange) {
                            return;
                        }
                        var addTime = new Date();
                        var comment = "Added from Greylist Report at " + addTime.toUTCString();
                        return $scope.$parent.addTrustedHost([ipOrRange], comment);
                    };

                    $scope.refresh = function() {
                        return $scope.fetch({ "isUpdate": false });
                    };

                    $scope.init = function() {
                        $scope.fetch({ "isUpdate": false });
                    };

                    $scope.init();
                }
            ]);

        return controller;
    }
);
