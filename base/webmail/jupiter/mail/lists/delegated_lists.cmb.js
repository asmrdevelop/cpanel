/*
# share/apps/mailinglists/src/services/mailingListsService       Copyright(c) 2020 cPanel, L.L.C.
#                                                                All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, YAHOO:false, angular:false */

/*
 * Creates a new MailingListItem
 * @class MailingListItem
 *
 * Used by MailingListService to store
 * each async loaded item
 *
 */
/* jshint -W100 */
function MailingListItem() {

    var _self = this;

    _self.defaultValues = {
        accesstype: "",
        advertised: 0,
        archive_private: 0,
        desthost: "",
        diskused: "",
        humandiskused: "00.00 KB",
        list: "",
        listadmin: "",
        listid: "",
        subscribe_policy: 0
    };
}

/*
 * @method create
 * Sets variables on the this object by merging
 * defaultValues and the rawData from the api
 *
 * benefits of this method are in the event that
 * if the rawData format ever changes, only this
 * bridge function will have to be altered.
 *
 * @param rawData {object} api generated response.data object
 */
MailingListItem.prototype.create = function(rawData) {
    angular.extend(this, this.defaultValues, rawData);
};

/*
 * @method getAttribute
 * Gets the attribute by the name (key)
 *
 * this is useful for the table because the columns
 * can be selected dynamically within an ngRepeat.
 *
 * @param key {string} name of attribute to fetch
 * @return attribute [key] {*}
 */
MailingListItem.prototype.getAttribute = function(key) {
    return this[key];
};

/*
 * @method formatListAdmin
 *
 * formats string to specified rows and columns
 *
 * @param settings {object} name of attribute to fetch
 * @param settings.maxItems {int} number of items / rows to display
 *        prepends "... and [N] more."
 * @param settings.maxCols {int} name of attribute to fetch
 * @param settings.separator {string} row separator
 * @return formatted string or html string based on settings
 */
MailingListItem.prototype.formatListAdmins = function(settings) {
    var input = this.getAttribute("listadmin");
    var defaultFormatSettings = {
        maxItems: input.length,
        maxCols: input.length,
        separator: "\n"
    };
    settings = angular.extend(defaultFormatSettings, settings);
    var admins = input.split(",");

    var excess;

    for (var i = 0; i < admins.length; i++) {
        var admin = admins[i].replace(/[\r\n]/gi, "").trim();
        if (admin.length > settings.maxCols) {
            admin = admin.substr(0, settings.maxCols - 3) + "…";
        }

        admins[i] = admin;

        if (i === settings.maxItems - 1 && i + 2 < admins.length) {
            excess = admins.length - settings.maxItems;
            admins.splice(i + 1); // empty out remaining items
            break;
        }
    }
    var out;

    if (excess) {
        out = LOCALE.maketext("[join,_1,_2][_1] … and [numf,_3] more", settings.separator, admins, excess);
    } else {
        out = admins.join(settings.separator);
    }

    return out;
};

/*
 * Creates a new MailingListService
 * @class MailingListService
 *
 * This serves as the model for the app
 * currently only retrieving the data
 * but also storing configurations for
 * that retreival
 *
 */
function MailingListService($rootScope, AlertService) {

    var _self = this;
    _self.lists = [];
    _self.loading = false;
    _self.alertService = AlertService;

    _self.page = 0;
    _self.pageSize = 10;
    _self.maxPages = 3;
    _self.totalResults = 0;
    _self.filterValue = "";
    _self.totalPages = 0;
    _self.errors = [];
    _self.request = null;

    _self.meta = {
        sort: {
            sortBy: "list",
            sortDirection: "asc",
            sortType: ""
        }
    };
    _self.meta.sort.sortString = "list";

    /*
     * @method addItem
     * factory function for creating and adding a new MailingListItem
     *
     * @param rawData {object} api generated response.data object
     */
    _self.addItem = function(rawData) {
        var item = new MailingListItem();
        item.create(rawData);
        _self.lists.push(item);
    };

    /*
     * @method handleLoadSuccess
     * success callback function for the api call below
     *
     * @param response {object} CPANEL.api response object
     */
    _self.handleLoadSuccess = function(response) {
        _self.lists = [];
        for (var i = 0; i < response.cpanel_data.length; i++) {
            _self.addItem(response.cpanel_data[i]);
        }
        var paginateData = response.cpanel_raw.metadata.paginate;
        if (typeof paginateData !== "undefined") {
            _self.totalPages = paginateData.total_pages;
            _self.totalResults = paginateData.total_results;
        }
        _self.loading = false;
        $rootScope.$apply();
    };

    /*
     * @method handleLoadError
     * error callback function for the api call below
     * currently just resets the "loading" param
     * and "$apply()s the empty list"
     * TODO: Add error messaging
     *
     * @param response {object} CPANEL.api response object
     */
    _self.handleLoadError = function(response) {
        _self.loading = false;
        _self.alertService.clear();
        angular.forEach(response.cpanel_messages, function(message) {
            _self.alertService.add({
                message: message.content,
                type: message.level
            });
        });
        $rootScope.$apply();
    };

    /*
     * @method selectPage
     * sets the current page and reloads the list
     *
     * @param page {number} number of the page to load
     */
    _self.selectPage = function() {
        _self.getLists();
    };

    /*
     * @method selectPageSize
     * sets number of items to pull per page
     * and reloads the list
     *
     * @param pageSize {number} number of items to display per page
     */
    _self.selectPageSize = function(pageSize) {

        _self.pageSize = pageSize;
        _self.getLists();
    };

    /*
     * @method dataSorted
     * on sorting of the data (from ToggleSortDirective)
     * rebuild the sortString and reload the list
     *
     * @param sortBy {string} key to sort by
     * @param sortDirection {string} [asc,desc] direction of the sort
     * @param sortType {string} [numeric, ...] how to handle the data being sorted
     */
    _self.dataSorted = function() {
        _self.meta.sort.sortString = _self.meta.sort.sortDirection === "asc" ? _self.meta.sort.sortBy : "!" + _self.meta.sort.sortBy;
        _self.getLists();
    };

    /*
     * @method getLists
     * reload lists from fresh api call
     * using stored parameters
     *
     */
    _self.getLists = function() {

        if (YAHOO.util.Connect.isCallInProgress(_self.request)) {
            YAHOO.util.Connect.abort(_self.request);
            _self.request = null;
        }

        _self.errors = [];

        var api_params = {
            module: "Email",
            version: "3",
            func: "list_lists",
            data: {
                domain: CPANEL.PAGE.domain
            },
            api_data: {
                sort: [],
                filter: []
            },
            callback: {
                success: _self.handleLoadSuccess,
                failure: _self.handleLoadError
            }
        };

        if (_self.meta.sort.sortBy === "humandiskused") {
            api_params.api_data.sort.push([(_self.meta.sort.sortDirection === "asc" ? "" : "!") + "diskused", "numeric"]);
        } else if (_self.meta.sort.sortString !== "") {
            api_params.api_data.sort.push(_self.meta.sort.sortString);
        }
        if (_self.filterValue !== "") {
            api_params.api_data.filter.push(["*", "contains", _self.filterValue]);
        }
        if (_self.pageSize !== -1) {
            api_params.api_data.paginate = {
                start: (_self.page - 1) * _self.pageSize,
                size: _self.pageSize
            };
        }

        _self.request = CPANEL.api(api_params);
        _self.loading = true;
    };

    if ("initData" in window.PAGE) {

        _self.totalResults = Number(window.PAGE.initData.totalResults) || 0;
        _self.totalPages = Number(window.PAGE.initData.totalPages) || 1;
        _self.pageSize = Number(window.PAGE.initData.resultsPerPage) || _self.pageSizes[0];

        for (var i = 0; i < window.PAGE.initData.lists.length; i++) {
            _self.addItem(window.PAGE.initData.lists[i]);
        }
    } else {
        _self.getLists();
    }

}

define(
    'app/services/mailingListsService',[

        // Libraries
        "angular",
        "cjt/util/locale",
        "cjt/services/alertService"
    ],
    function(angular) {

        // Fetch the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        MailingListService.$inject = ["$rootScope", "alertService"];
        app.service("mailingListsService", MailingListService);
    }
);

/*
# share/apps/mailinglists/src/views/mailingListsController    Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                        http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/controllers/mailingListsController',[
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

/*
# share/apps/mailinglists/src/views/mainController          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/* TABLE ControllerCode */

define(
    'app/controllers/mainController',[
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

/*
# cpanel - base/webmail/jupiter/mail/lists/delegated_lists.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    'app/delegated_lists',[
        "angular",
        "cjt/modules",
    ],
    function(angular) {
        "use strict";

        var app = angular.module("App", ["ui.bootstrap", "cjt2.webmail"]);

        /*
         * this looks funky, but these require that
         * angular be loaded before they can be loaded
         * so the nested requires become relevant
         */
        app = require(
            [
                "cjt/directives/toggleSortDirective",
                "cjt/directives/spinnerDirective",
                "cjt/directives/searchDirective",
                "cjt/directives/pageSizeDirective",
                "app/services/mailingListsService",
                "app/controllers/mailingListsController",
                "app/controllers/mainController",
                "uiBootstrap",
            ],
            function() {

                var app = angular.module("App");

                // app.config(["$provide", Decorate]);

                /*
                 * filter used to escape emails and urls
                 * using native js escape
                 */
                app.filter("escape", function() {
                    return window.escape;
                });

                /*
                 * because of the race condition with the dom loading and angular loading
                 * before the establishment of the app
                 * a manual initiation is required
                 * and the ng-app is left out of the dom
                 */
                app.init = function() {
                    var appContent = angular.element("#content");

                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        angular.bootstrap(appContent[0], ["App"]);
                    }

                    return app;
                };
                app.init();
            });

        return app;
    }
);

