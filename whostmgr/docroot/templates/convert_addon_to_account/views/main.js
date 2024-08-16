/*
# views/main.js                                    Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "uiBootstrap",
        "cjt/decorators/growlDecorator",
        "cjt/directives/searchDirective",
        "app/services/ConvertAddonData"
    ],
    function(angular, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "mainController",
            ["$anchorScroll", "$location", "growl", "ConvertAddonData",
                function($anchorScroll, $location, growl, ConvertAddonData) {

                    var main = this;

                    main.allDomains = [];
                    main.loadingDomains = false;

                    main.meta = {
                        sortDirection: "asc",
                        sortBy: "domain",
                        sortType: "",
                        sortReverse: false,
                        maxPages: 0,
                        totalItems: main.allDomains.length || 0,
                        pageNumber: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100],
                        pagedList: [],
                        filteredList: main.allDomains,
                        filter: ""
                    };

                    main.resetPagination = function() {
                        main.meta.pageNumber = 1;
                        main.fetchPage();
                    };

                    main.includeItem = function(domainInfo) {
                        if (domainInfo.addon_domain.indexOf(main.meta.filter) !== -1 ||
                        domainInfo.owner.indexOf(main.meta.filter) !== -1) {
                            return true;
                        }
                        return false;
                    };

                    main.filterList = function() {
                        main.meta.filteredList = main.allDomains.filter(main.includeItem);
                        main.resetPagination();
                    };

                    main.clearFilter = function() {
                        if (main.hasFilter()) {
                            main.meta.filter = "";
                            main.meta.filteredList = main.allDomains.slice();
                            main.resetPagination();
                        }
                    };

                    main.hasFilter = function() {
                        return main.meta.filter.length > 0;
                    };

                    main.fetchPage = function(scrollToTop) {
                        var pageSize = main.meta.pageSize;
                        var beginIndex = ((main.meta.pageNumber - 1) * pageSize) + 1;
                        var endIndex = beginIndex + pageSize - 1;
                        if (endIndex > main.meta.filteredList.length) {
                            endIndex = main.meta.filteredList.length;
                        }

                        main.meta.totalItems = main.meta.filteredList.length;
                        main.meta.pagedList = main.meta.filteredList.slice(beginIndex - 1, endIndex);
                        main.meta.pageNumberStart = main.meta.filteredList.length === 0 ? 0 : beginIndex;
                        main.meta.pageNumberEnd = endIndex;

                        if (scrollToTop) {
                            $anchorScroll("pageContainer");
                        }
                    };

                    main.paginationMessage = function() {
                        return LOCALE.maketext("Displaying [numf,_1] to [numf,_2] out of [quant,_3,item,items]", main.meta.pageNumberStart, main.meta.pageNumberEnd, main.meta.totalItems);
                    };

                    main.convertDomain = function(domainInfo) {
                        $location.path("/convert/" + encodeURIComponent(domainInfo.addon_domain) + "/migrations");
                    };

                    main.compareDomains = function(domainA, domainB) {
                        if (main.meta.sortBy === "domain") {
                            return domainA.addon_domain.localeCompare(domainB.addon_domain);
                        } else { // sort by owner
                            var ownerComparison = domainA.owner.localeCompare(domainB.owner);
                            if (ownerComparison === 0) {

                            // if the owners are the same, sort by domain
                                return domainA.addon_domain.localeCompare(domainB.addon_domain);
                            }
                            return ownerComparison;
                        }
                    };

                    main.sortList = function() {
                        main.allDomains.sort(main.compareDomains);

                        if (main.meta.sortDirection !== "asc") {
                            main.allDomains = main.allDomains.reverse();
                        }
                    };

                    main.hasAddonDomains = function() {
                        return main.meta.pagedList.length > 0;
                    };

                    main.resetDisplay = function() {
                        main.sortList();
                        main.filterList();
                    };

                    main.loadList = function() {
                        main.loadingDomains = true;
                        return ConvertAddonData.loadList()
                            .then(
                                function(result) {
                                    main.allDomains = result;
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally( function() {
                                main.loadingDomains = false;
                                main.resetDisplay();
                            });
                    };

                    main.forceLoadList = function() {
                        main.allDomains = [];
                        main.meta.pagedList = [];
                        main.loadList();
                    };

                    main.viewHistory = function() {
                        $location.path("/history/");
                    };

                    main.init = function() {
                        if (app.firstLoad.addonList) {
                            app.firstLoad.addonList = false;
                            main.allDomains = ConvertAddonData.domains;
                            main.resetDisplay();
                        } else {
                            main.loadList();
                        }
                    };

                    main.init();
                }
            ]);

        return controller;
    }
);
