/*
# templates/mod_security/views/vendorListController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/responsiveSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/vendorService",
        "cjt/io/whm-v1-querystring-service"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "vendorListController", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$routeParams",
                "$timeout",
                "vendorService",
                "alertService",
                "spinnerAPI",
                "queryService",
                "PAGE",
                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $routeParams,
                    $timeout,
                    vendorService,
                    alertService,
                    spinnerAPI,
                    queryService,
                    PAGE) {

                    /**
                         * Load the edit vendor view with the  requested vendor.
                         *
                         * @method loadEditVendorView
                         * @param  {Object} vendor
                         * @param  {Boolean} force if true, will show the special warning.
                         */
                    $scope.loadEditVendorView = function(vendor, force) {
                        var args = { id: vendor.vendor_id };
                        if (typeof (force) !== "undefined" && force === true) {
                            args["force"] = true.toString();
                        }
                        $scope.loadView("vendors/edit", args);
                    };

                    /**
                         * Clear the search query
                         *
                         * @method clearFilter
                         * @return {Promise}
                         */
                    $scope.clearFilter = function() {
                        $scope.meta.filterValue = "";
                        $scope.activeSearch = false;
                        $scope.filteredData = false;

                        // Leave history so refresh works
                        queryService.query.clearSearch();

                        // select the first page of search results
                        return $scope.selectPage(1);
                    };

                    /**
                         * Start a search query
                         *
                         * @method startFilter
                         * @return {Promise}
                         */
                    $scope.startFilter = function() {
                        $scope.activeSearch = true;
                        $scope.filteredData = false;

                        // Leave history so refresh works
                        queryService.query.clearSearch();
                        queryService.query.addSearchField("*", "contains", $scope.meta.filterValue);

                        return $scope.selectPage(1)
                            .then(function() {
                                $scope.filteredData = true;
                            });
                    };

                    /**
                         * Select a specific page of vendors
                         *
                         * @method selectPage
                         * @param  {Number} [page] Optional page number, if not provided will use the current
                         * page provided by the scope.meta.pageNumber.
                         * @return {Promise}
                         */
                    $scope.selectPage = function(page) {

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.pageNumber = page;
                        }

                        // Leave history so refresh works
                        queryService.query.updatePagination($scope.meta.pageNumber, $scope.meta.pageSize);

                        return $scope.fetch();
                    };

                    /**
                         * Sort the list of rules
                         *
                         * @param {Object}  meta         The sort model.
                         * @param {Boolean} defaultSort  If true, the sort was not not initiated by the user
                         */
                    $scope.sortList = function(meta, defaultSort) {
                        queryService.query.clearSort();
                        queryService.query.addSortField(meta.sortBy, meta.sortType, meta.sortDirection);

                        if (!defaultSort) {
                            $scope.fetch();
                        }
                    };

                    /**
                         * Handles the keybinding for the clearing and searching.
                         * Esc clears the search field.
                         * Enter performs a search.
                         *
                         * @method triggerToggleSearch
                         * @param {Event} event - The event object
                         */
                    $scope.triggerToggleSearch = function(event) {

                        // clear on Esc
                        if (event.keyCode === 27) {
                            $scope.toggleSearch(true);
                        }

                        // filter on Enter
                        if (event.keyCode === 13) {
                            $scope.toggleSearch();
                        }
                    };

                    /**
                         * Toggles the clear button and conditionally performs a search.
                         * The expected behavior is if the user clicks the button or focuses the button and hits enter the button state rules.
                         *
                         * @method toggleSearch
                         * @param {Boolean} isClick Toggle button clicked.
                         * @return {Promise}
                         */
                    $scope.toggleSearch = function(isClick) {
                        var filter = $scope.meta.filterValue;

                        if ( !filter && ($scope.activeSearch  || $scope.filteredData)) {

                            // no query in box, but we prevously filtered or there is an active search
                            return $scope.clearFilter();
                        } else if (isClick && $scope.activeSearch ) {

                            // User clicks clear
                            return $scope.clearFilter();
                        } else if (filter) {
                            return $scope.startFilter();
                        }
                    };

                    /**
                         * Fetch the list of hits from the server
                         *
                         * @method fetch
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.fetch = function() {
                        spinnerAPI.start("loadingSpinner");
                        return vendorService
                            .fetchList($scope.meta)
                            .then(function(results) {
                                $scope.vendors = results.items;
                                $scope.totalItems = results.totalItems;
                                $scope.totalPages = results.totalPages;
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorFetch"
                                });
                            })
                            .then(function() {
                                $scope.loading = false;
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    /**
                         * Set status of a specific vendor.
                         *
                         * @method setVenderStatus
                         * @param  {Object} vendor
                         * @return {Promise} Promise that when fulfilled will result in the vendor status being saved.
                         */
                    $scope.setVenderStatus = function(vendor) {
                        spinnerAPI.start("loadingSpinner");
                        if ( vendor.enabled ) {
                            return vendorService
                                .enableVendor(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.enabled = true;

                                    if (vendor.in_use === 0) {
                                        $scope.loadEditVendorView(vendor, true);
                                    } else {

                                        // success
                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("You have successfully enabled the vendor: [_1]", vendor.name),
                                            id: "enableSuccess"
                                        });
                                    }
                                }, function(error) {

                                    // failure
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "enableFailed"
                                    });
                                    vendor.enabled = false;
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        } else {
                            return vendorService
                                .disableVendor(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.enabled = false;

                                    // success
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully disabled the vendor: [_1]", vendor.name),
                                        id: "disableSuccess"
                                    });
                                }, function(error) {

                                    // failure
                                    alertService.add( {
                                        type: "danger",
                                        message: error,
                                        id: "disableFailed"
                                    });
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        }
                    };

                    /**
                         * Sets automatic updates for a vendor.
                         *
                         * @method setVenderUpdate
                         * @param  {Object} vendor
                         * @return {Promise} Promise that, when fulfilled, will result in the update status of a vender being saved.
                         */
                    $scope.setVenderUpdate = function(vendor) {
                        spinnerAPI.start("loadingSpinner");
                        if ( vendor.update ) {
                            return vendorService
                                .enableVendorUpdates(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.update = true;
                                    alertService.add( {
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully enabled automatic updates for the vendor: [_1]", vendor.name),
                                        id: "enableUpdatesSuccess"
                                    } );
                                }, function(error) {
                                    alertService.add( {
                                        type: "danger",
                                        message: error,
                                        id: "enableUpdatesFailed"
                                    } );
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        } else {
                            return vendorService
                                .disableVendorUpdates(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.update = false;
                                    alertService.add( {
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully disabled automatic updates for the vendor: [_1]", vendor.name),
                                        id: "disableUpdatesSuccess"
                                    } );
                                }, function(error) {
                                    alertService.add( {
                                        type: "danger",
                                        message: error,
                                        id: "disableUpdatesFailed"
                                    } );
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        }
                    };

                    /**
                         * Install the vendor on your system.
                         *
                         * @method install
                         * @param  {Object} vendor
                         * @return {Promise} Promise that when fulfilled will result in the vendor being installed on your system.
                         */
                    $scope.install = function(vendor) {
                        vendor.installing = true;
                        return vendorService
                            .saveVendor(vendor.installed_from)
                            .then(function() {
                                vendor.installed = true;

                                // Report success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully installed the vendor: [_1]", vendor.name),
                                    id: "installSuccess"
                                });

                                spinnerAPI.stop("loadingSpinner");

                                return $scope.fetch();
                            }, function(error) {

                                // failure
                                alertService.add( {
                                    type: "danger",
                                    message: LOCALE.maketext("The system experienced the following error when it attempted to install the “[_1]” vendor: [_2]", vendor.name, error),
                                    id: "installFailed"
                                });

                                throw error;
                            }).finally(function() {

                                // remove the process flag even if the process failed
                                delete vendor.installing;
                            });
                    };

                    /**
                         * Remove the vendor from your system.
                         *
                         * @method delete
                         * @param  {Object} vendor
                         * @return {Promise} Promise that when fulfilled will result in the vendor being removed from your system.
                         */
                    $scope.delete = function(vendor) {
                        vendor.deleting = true;
                        return vendorService
                            .deleteVendor(vendor.vendor_id)
                            .then(function() {

                                // Report success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully removed the vendor: [_1]", vendor.name),
                                    id: "deleteSuccess"
                                });

                                return $scope.fetch();
                            }, function(error) {

                                // We are done deleting so remove
                                // the signaling flag.
                                delete vendor.deleting;

                                // failure
                                alertService.add( {
                                    type: "danger",
                                    message: LOCALE.maketext("The system experienced the following error when it attempted to remove the vendor [_1]: [_2]", vendor.name, error),
                                    id: "deleteFailed"
                                });

                                throw error;
                            });
                    };

                    /**
                         * Test if the current vendor is being deleted.
                         *
                         * @method isDeleting
                         * @param  {Ojbect}  vendor
                         * @return {Boolean}        true if the current vendor being deleted, false otherwise.
                         */
                    $scope.isDeleting = function(vendor) {
                        return vendor.deleting;
                    };

                    /**
                         * Show the delete confirm dialog for the vendor. Will close any other open confirms first.
                         *
                         * @method showDeleteConfirm
                         * @param  {Object} vendor
                         */
                    $scope.showDeleteConfirm = function(vendor) {
                        if (vendor.is_pkg) {
                            window.location.assign("../../scripts7/EasyApache4/review?uninstall=" + vendor.is_pkg);
                            return true;
                        }

                        if ($scope.lastConfirm) {

                            // Close the last one
                            delete $scope.lastConfirm.deleteConfirm;
                            delete $scope.lastConfirm.installConfirm;
                        }
                        vendor.deleteConfirm = true;
                        $scope.lastConfirm = vendor;
                    };

                    /**
                         * Hide the delete confirm dialog for the vendor
                         *
                         * @method hideDeleteConfirm
                         * @param  {Object} vendor
                         */
                    $scope.hideDeleteConfirm = function(vendor) {
                        delete vendor.deleteConfirm;
                    };

                    /**
                         * Test if the delete confirm dialog for a vendor should be shown.
                         *
                         * @method canShowDeleteConfirm
                         * @param  {Object} vendor
                         * @return {Boolean} true if the current vendor should show the confirmation, false otherwise.
                         */
                    $scope.canShowDeleteConfirm = function(vendor) {

                        // cast the value since it can be undefined
                        return !!vendor.deleteConfirm;
                    };

                    /**
                         * Test whether the vendor is installed.
                         *
                         * @method isVendorInstalled
                         * @param  {Object} vendor
                         * @return {Booelan} true if the vendor is installed, false otherwise.
                         */
                    $scope.isVendorInstalled = function(vendor) {
                        return vendor.installed;
                    };

                    /**
                         * Test if the current vendor is being installed.
                         * dialog.
                         *
                         * @method isInstalling
                         * @param  {Ojbect} vendor
                         * @return {Boolean} true if the current vendor being installed, false otherwise.
                         */
                    $scope.isInstalling = function(vendor) {
                        return vendor.installing;
                    };

                    /**
                         * Show the install confirm dialog for the vendor. Will close any other open confirms first.
                         *
                         * @method showInstallConfirm
                         * @param  {Object} vendor
                         */
                    $scope.showInstallConfirm = function(vendor) {
                        if ($scope.lastConfirm) {

                            // Close the last one
                            delete $scope.lastConfirm.deleteConfirm;
                            delete $scope.lastConfirm.installConfirm;
                        }
                        vendor.installConfirm = true;
                        $scope.lastConfirm = vendor;
                    };

                    /**
                         * Hide the install confirm dialog for the vendor
                         *
                         * @method hideInstallConfirm
                         * @param  {Object} vendor
                         */
                    $scope.hideInstallConfirm = function(vendor) {
                        delete vendor.installConfirm;
                    };

                    /**
                         * Test if the install confirm dialog for a vendor should be shown.
                         *
                         * @method canShowInstallConfirm
                         * @param  {Object} vendor
                         * @return {Boolean} true if the current vendor should show the confirmation, false otherwise.
                         */
                    $scope.canShowInstallConfirm = function(vendor) {

                        // cast the value since it can be undefined
                        return !!vendor.installConfirm;
                    };

                    /**
                         * Test if the row dialog for a vendor should be shown.
                         *
                         * @method shouldShowDialog
                         * @param  {Object} vendor
                         * @return {Boolean} true if the vendor is being deleted or is not installed, false otherwise.
                         */
                    $scope.shouldShowDialog = function(vendor) {
                        return $scope.canShowDeleteConfirm(vendor) || $scope.canShowInstallConfirm(vendor);
                    };

                    // setup data structures for the view
                    $scope.loading = true;

                    // Items accounting
                    $scope.vendors = [];
                    $scope.totalPages = 0;
                    $scope.totalItems = 0;

                    // Filter related flags
                    $scope.activeSearch = false;
                    $scope.filteredData = false;
                    $scope.lastConfirm = null;

                    // Meta-data for lister filter, sort and pagination
                    var hasPaging = queryService.route.hasPaging();
                    var pageSize = queryService.DEFAULT_PAGE_SIZE;
                    var page = 1;
                    if (hasPaging) {
                        pageSize = queryService.route.getPageSize();
                        page = queryService.route.getPage();
                    }

                    var sorting = queryService.route.getSortProperties("enabled", "", "asc");
                    var hasFilter = queryService.route.hasSearch();
                    var filterRules = queryService.route.getSearch();

                    $scope.meta = {
                        filterBy: hasFilter ? filterRules[0].field : "*",
                        filterCompare: hasFilter ? filterRules[0].type : "contains",
                        filterValue: hasFilter ? filterRules[0].value : "",
                        pageSize: hasPaging ?  pageSize : queryService.DEFAULT_PAGE_SIZE,
                        pageNumber: hasPaging ? page : 1,
                        sortDirection: sorting.direction,
                        sortBy: sorting.field,
                        sortType: sorting.type,
                        pageSizes: queryService.DEFAULT_PAGE_SIZES
                    };

                    // if the user types something else in the search box, we change the button icon so they can search again.
                    $scope.$watch("meta.filterValue", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.activeSearch = false;
                    });

                    // watch the page size and and load the first page if it changes
                    $scope.$watch("meta.pageSize", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.selectPage(1);
                    });

                    // Determine if we have an active search on load
                    $scope.activeSearch = $scope.filteredData = $scope.meta.filterValue ? true : false;

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    // Expose any backend exceptions
                    $scope.exception = queryService.prefetch.failed(PAGE.vendors) ? queryService.prefetch.getMetaMessage(PAGE.vendors) : "";

                    // check for page data in the template if this is a first load
                    if (app.firstLoad.vendors && PAGE.vendors) {
                        app.firstLoad.vendors = false;
                        $scope.loading = false;
                        var results = vendorService.prepareList(PAGE.vendors);
                        $scope.vendors = results.items;
                        $scope.totalItems = results.totalItems;
                        $scope.totalPages = results.totalPages;
                    } else {

                        // Otherwise, retrieve it via ajax
                        $timeout(function() {

                            // NOTE: Without this delay the spinners are not created on inter-view navigation.
                            $scope.selectPage(1);
                        });
                    }
                }
            ]
        );

        return controller;
    }
);
