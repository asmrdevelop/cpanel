/*
# services/pageDataService.js                     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/pageDataService',[
        "angular"
    ],
    function(angular) {

        // Fetch the current application
        var app = angular.module("App");

        /**
         * Setup the domainlist models API service
         */
        app.factory("pageDataService", [ function() {

            return {

                /**
                 * Helper method to remodel the default data passed from the backend
                 * @param  {Object} defaults - Defaults object passed from the backend
                 * @return {Object}
                 */
                prepareDefaultInfo: function(defaults) {
                    defaults.security_token = defaults.security_token || "";
                    defaults.addon_domains = defaults.addon_domains || [];
                    defaults.username_restrictions = defaults.username_restrictions || {};
                    defaults.username_restrictions.maxLength = Number(defaults.username_restrictions.maxLength) || 16;
                    return defaults;
                }

            };
        }]);
    }
);

/*
# templates/convert_addon_to_account/services/ConvertAddonData.js Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/ConvertAddonData',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var convertAddonData = app.factory("ConvertAddonData", ["$q", "defaultInfo", function($q, defaultInfo) {

            var addonData = {};

            addonData.domains = [];
            var default_options = {
                "email-accounts": true,
                "autoresponders": true,
                "email-forwarders": true,
                "docroot": true,
                "preserve-ownership": true,
                "custom-dns-records": true,
                "mysql_dbs": [],
                "mysql_users": [],
                "db_move_type": "move",
                "custom-vhost-includes": true,
                "copy-installed-ssl-cert": true,
                "ftp-accounts": true,
                "webdisk-accounts": true
            };

            function _getAddonData(domain) {
                var data = addonData.domains.filter(function(domain_data) {
                    return domain === domain_data.addon_domain;
                });
                return (data.length) ? data[0] : {};
            }

            /**
             * Fetch the addon domain
             *
             * @method getAddonDomain
             * @param {string} addonDomain - the addon domain you want to get
             * @returns A Promise that resolves to an object for the addon domain
             */
            addonData.getAddonDomain = function(addonDomain) {

                // If the domains data is empty, then we should fetch the data first
                if (addonData.domains.length === 0) {
                    return $q.when(addonData.loadList())
                        .then(function(result) {
                            return _getAddonData(addonDomain);
                        });
                } else {
                    return $q.when(_getAddonData(addonDomain));
                }
            };

            addonData.getAddonDomainDetails = function(addonDomain) {

                // if we already fetched the details previously, shortcircuit this api call
                var found = _getAddonData(addonDomain);
                if (Object.keys(found).length > 1 && Object.keys(found.details).length > 1) {
                    return $q.when(found);
                } else {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "convert_addon_fetch_domain_details");
                    apiCall.addArgument("domain", addonDomain);

                    return $q.when(API.promise(apiCall.getRunArguments()))
                        .then(function(response) {
                            response = response.parsedResponse;

                            // update this addon domain in the data structure
                            // with the details
                            return addonData.getAddonDomain(addonDomain)
                                .then(function(result) {
                                    if (response.data !== null) {
                                        angular.extend(result.details, response.data);

                                        // if the addon domain has no options, initialize it with some
                                        if (Object.keys(result.move_options).length === 0) {
                                            angular.extend(result.move_options, default_options);
                                        }
                                    }

                                    return result;
                                });
                        })
                        .catch(function(response) {
                            response = response.parsedResponse;
                            return response.error;
                        });
                }
            };

            addonData.convertDomainObjectToList = function(domainObject) {
                addonData.domains = Object.keys(domainObject).map(function(domainName) {
                    var domainDetail = domainObject[domainName];
                    domainDetail.addon_domain = domainName;
                    domainDetail.details = {};
                    domainDetail.move_options = {};
                    domainDetail.account_settings = {};
                    return domainDetail;
                });
            };

            addonData.loadList = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_list_addon_domains");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            addonData.convertDomainObjectToList(response.data);
                            deferred.resolve(addonData.domains);
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };

            addonData.beginConversion = function(addon) {
                var i, len;
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_initiate_conversion");

                for (var setting in addon.account_settings) {
                    if (addon.account_settings.hasOwnProperty(setting)) {
                        apiCall.addArgument(setting, addon.account_settings[setting]);
                    }
                }

                for (var service in addon.move_options) {
                    if (addon.move_options.hasOwnProperty(service)) {

                        // ignore this value
                        if (service === "db_move_type") {
                            continue;
                        }

                        if (service === "mysql_dbs") {
                            for (i = 0, len = addon.move_options[service].length; i < len; i++) {
                                if (addon.move_options.db_move_type === "copy") {
                                    apiCall.addArgument("copymysqldb-" + addon.move_options[service][i].name,
                                        addon.move_options[service][i].new_name);
                                } else {
                                    apiCall.addArgument("movemysqldb-" + i, addon.move_options[service][i].name);
                                }
                            }
                        } else if (service === "mysql_users" && addon.move_options.db_move_type === "move") {
                            for (i = 0, len = addon.move_options[service].length; i < len; i++) {
                                apiCall.addArgument("movemysqluser-" + i, addon.move_options[service][i].name);
                            }
                        } else {

                            // The backend expects boolean options to use 1 or 0
                            if (_.isBoolean(addon.move_options[service])) {
                                apiCall.addArgument(service, (addon.move_options[service]) ? 1 : 0);
                            } else {
                                apiCall.addArgument(service, addon.move_options[service]);
                            }
                        }
                    }
                }

                return $q.when(API.promise(apiCall.getRunArguments()))
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            return response.data;
                        } else {
                            return $q.reject(response.meta);
                        }
                    });
            };

            addonData.init = function() {
                addonData.convertDomainObjectToList(defaultInfo.addon_domains);
            };

            addonData.init();

            return addonData;
        }]);

        return convertAddonData;
    }
);

/*
# convert_addon_to_account/services/Databases.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/Databases',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var databasesFactory = app.factory("Databases", ["$q", function($q) {

            var db = {};

            db.databases = {};
            db.users = {};
            db.currentOwner = "";

            var uses_prefixing;
            var mysql_version;
            var prefix_length;

            // these are functions that exist in the old cjt/sql.js
            var verify_func_name = {
                mysql: {
                    database: "verify_mysql_database_name"
                },
                postgresql: {
                    database: "verify_postgresql_database_name"
                }
            };

            db.setPrefixing = function(option) {
                uses_prefixing = option;
            };

            db.isPrefixingEnabled = function() {
                return uses_prefixing;
            };

            db.setMySQLVersion = function(version) {
                mysql_version = version;

                // this has to be exported for the old cjt/sql.js to work correctly
                window.MYSQL_SERVER_VERSION = mysql_version;
            };

            db.getMySQLVersion = function() {
                return mysql_version;
            };

            db.setPrefixLength = function(length) {
                prefix_length = length;
            };

            db.getPrefixLength = function() {
                return prefix_length;
            };

            db.createPrefix = function(user) {

                /*
                 * Transfers and some older accounts might have underscores or periods
                 * in the cpusername. For historical reasons, the account's "main" database
                 * username always strips these characters out.
                 * In 99% of cases, this function is a no-op.
                 */
                var username = user.replace(/[_.]/, "");

                var prefixLength = db.getPrefixLength();
                return username.substr(0, prefixLength) + "_";
            };

            db.addPrefix = function(database, user) {
                return db.createPrefix(user) + database;
            };

            db.addPrefixIfNeeded = function(database, user) {
                if (database === void 0 || database === "") {
                    return;
                }

                var prefix = db.createPrefix(user);
                var prefix_regex = new RegExp("^" + prefix + ".+$");

                // if the db already has a prefix, just return it
                if (prefix_regex.test(database)) {
                    return database;
                }

                // else, return the database with the prefix
                return prefix + database;
            };

            /**
             * Transform the data from the API call into a
             * map of users and their corresponding databases.
             *
             * @method createUsersDictionary
             * @param {Object} data - the data returned from the
             * list_mysql_databases_and_users API call
             * return {Object} an object where the keys are db users and values are
             * their associated databases.
             */
            function createUsersDictionary(data) {
                var usersObj = {};
                var user = "";
                var dbs = data.mysql_databases;

                for (var database in dbs) {
                    if (dbs.hasOwnProperty(database)) {
                        for (var i = 0, len = dbs[database].length; i < len; i++) {
                            user = dbs[database][i];
                            if (usersObj.hasOwnProperty(user)) {
                                usersObj[user].push(database);

                            } else {
                                usersObj[user] = [database];
                            }
                        }
                    }
                }

                return usersObj;
            }

            db.listMysqlDbsAndUsers = function(owner) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "list_mysql_databases_and_users");
                apiCall.addArgument("user", owner);

                return $q.when(API.promise(apiCall.getRunArguments()))
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            db.setPrefixing(PARSE.parsePerlBoolean(response.data.mysql_config.use_db_prefix));
                            db.setPrefixLength(response.data.mysql_config.prefix_length);
                            db.setMySQLVersion(response.data.mysql_config["mysql-version"]);
                            db.databases = response.data.mysql_databases;
                            db.users = createUsersDictionary(response.data);
                        } else {
                            return $q.reject(response.meta);
                        }
                    });
            };

            /**
             * Get the databases from the service. This will call the API
             * if there are no databases stored in the service.
             *
             * @method getDatabases
             * @param {String} owner - the owner of the databases
             * @return {Promise} a promise that resolves to a dictionary of databases for the owner
             */
            db.getDatabases = function(owner) {
                if (Object.keys(db.databases).length > 0 && db.currentOwner === owner) {
                    return $q.when(db.databases);
                } else {
                    return db.listMysqlDbsAndUsers(owner)
                        .then(function() {
                            db.currentOwner = owner;
                            return db.databases;
                        });
                }
            };

            /**
             * Get the users from the service.
             *
             * @method getUsers
             * @return {Object} a dictionary of mysql users
             */
            db.getUsers = function() {
                return db.users;
            };

            db.validateName = function(name, engine) {
                return CPANEL.sql[verify_func_name[engine]["database"]](name);
            };

            return db;
        }]);

        return databasesFactory;
    }
);

/*
# convert_addon_to_account/services/account_packages.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/account_packages',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var packagesFactory = app.factory("AccountPackages", ["$q", function($q) {

            var pkg = {};

            pkg.packages = [];

            /**
             * Fetch the list of packages from the listpkgs API call.
             *
             * @method listPackages
             * return {Promise} a promise that on success, returns an array of packages
             * and on error, an error object.
             */
            pkg.listPackages = function() {
                if (pkg.packages.length > 0) {
                    return $q.when(pkg.packages);
                } else {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "listpkgs");

                    return $q.when(API.promise(apiCall.getRunArguments()))
                        .then(function(response) {
                            response = response.parsedResponse;
                            if (response.status) {
                                pkg.packages = response.data;
                                return pkg.packages;
                            } else {
                                return $q.reject(response.meta);
                            }
                        });
                }
            };

            return pkg;
        }]);

        return packagesFactory;
    }
);

/*
# convert_addon_to_account/services/conversion_history.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/conversion_history',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ],
    function(angular, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        var app = angular.module("App");

        var conversionHistory = app.factory("ConversionHistory", ["$q", function($q) {

            var store = {};
            store.conversions = [];

            /**
             * Gets the details for a conversion
             *
             * @method getDetails
             * @param {Number} job_id - The job id of the desired conversion.
             * @return {Object} An object consisting of conversion details and steps.
             */

            store.getDetails = function(job_id) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_fetch_conversion_details");
                apiCall.addArgument("job_id", job_id);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * Gets the current status for a conversion
             *
             * @method getJobStatus
             * @param {Number} job_ids - An array job ids of the desired conversions.
             * @return {Object} An object consisting of status information
             */

            store.getJobStatus = function(job_ids) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_get_conversion_status");
                var jobIdCount = job_ids.length;
                var i = 0;

                for (; i < jobIdCount; i++) {
                    apiCall.addArgument("job_id" + "-" + i, job_ids[i]);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * Fetches all the conversion jobs
             *
             * @method load
             * @return {Array} An arrary of conversion jobs.
             */
            store.load = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_list_conversions");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            store.conversions = response.data;
                            deferred.resolve(store.conversions);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            return store;
        }]);

        return conversionHistory;
    }
);

/*
# convert_addon_to_account/filters/local_datetime_filter.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define('app/filters/local_datetime_filter',["angular", "cjt/util/locale"], function(angular, LOCALE) {

    var app = angular.module("App");
    app.filter("local_datetime", function() {
        return function(input) {
            if (input === void 0 || input === null || input === "") {
                return "";
            }

            if (typeof input !== "number") {
                input = Number(input);
            }

            return LOCALE.local_datetime(input, "datetime_format_medium");
        };
    });

});

/*
# views/main.js                                    Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/main',[
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

/*
# directives/move_status.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/move_status',[
        "angular",
        "cjt/util/locale",
        "cjt/core",
    ],
    function(angular, LOCALE, CJT) {

        var app = angular.module("App");
        app.directive("itemMoveStatus",
            [
                function() {
                    var TEMPLATE_PATH = "directives/move_status.phtml";
                    var RELATIVE_PATH = "templates/convert_addon_to_account/" + TEMPLATE_PATH;
                    var MOVE_TEXT = LOCALE.maketext("Selected");
                    var DO_NOT_MOVE_TEXT = LOCALE.maketext("Not Selected");

                    return {
                        replace: true,
                        require: "ngModel",
                        restrict: "E",
                        scope: {
                            ngModel: "=",
                        },
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        link: function(scope, element, attrs) {
                            scope.moveLabel = MOVE_TEXT;
                            scope.noMoveLabel = DO_NOT_MOVE_TEXT;
                        }
                    };
                }
            ]);
    }
);

/*
# views/move_options.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/move_options',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "cjt/validator/email-validator",
        "cjt/directives/validationItemDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validateEqualsDirective",
        "cjt/directives/actionButtonDirective",
        "app/services/ConvertAddonData",
        "app/services/Databases",
        "app/services/account_packages",
        "app/directives/move_status",
    ],
    function(angular, LOCALE) {

        var app = angular.module("App");

        var controller = app.controller(
            "moveSelectionController",
            ["$q", "$location", "$routeParams", "defaultInfo", "growl", "ConvertAddonData", "Databases", "AccountPackages", "$scope",
                function($q, $location, $routeParams, defaultInfo, growl, ConvertAddonData, Databases, AccountPackages, $scope) {
                    var move_options_vm = this;

                    move_options_vm.ui = {};
                    move_options_vm.ui.is_loading = false;
                    move_options_vm.ui.domain_exists = false;
                    move_options_vm.ui.is_conversion_started = false;
                    move_options_vm.enable_db_button = false;
                    move_options_vm.this_domain = {};
                    move_options_vm.copy_mysql_dbs = false;
                    move_options_vm.has_dedicated_ip = false;
                    move_options_vm.account_packages = [];
                    move_options_vm.ip_addr_will_change = false;
                    move_options_vm.selected_package = void 0;

                    move_options_vm.stats = {};

                    move_options_vm.no_databases_tooltip = LOCALE.maketext("Disabled because there are no databases to move");
                    move_options_vm.no_email_tooltip = LOCALE.maketext("Disabled because there are no email-related items to move");

                    // initialize the view
                    function init() {
                        move_options_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomainDetails($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    move_options_vm.domain_name = data.addon_domain;
                                    move_options_vm.this_domain = data;

                                    move_options_vm.this_domain.account_settings.domain = data.addon_domain;
                                    if (move_options_vm.this_domain.account_settings.email === void 0) {
                                        move_options_vm.this_domain.account_settings.email = "";
                                    }

                                    if (move_options_vm.this_domain.account_settings.pkgname === void 0) {
                                        move_options_vm.this_domain.account_settings.pkgname = "";
                                    }

                                    if (move_options_vm.this_domain.account_settings.username === void 0) {
                                        move_options_vm.generate_username(move_options_vm.domain_name);
                                    }

                                    if (move_options_vm.this_domain.details.has_dedicated_ip === 1) {
                                        move_options_vm.ip_addr_will_change = true;
                                    }

                                    // we only want to show the SSL certificate copy option if the user has chosen to copy the ssl cert
                                    // and they have an SSL cert installed for that domain
                                    move_options_vm.show_ssl_copy_option = move_options_vm.this_domain.move_options["copy-installed-ssl-cert"] &&
                                    move_options_vm.this_domain.details.has_ssl_cert_installed === 1;

                                    // intelligently set some options based on the data we have
                                    if (!move_options_vm.this_domain.modified) {
                                        change_defaults(move_options_vm.this_domain);
                                        move_options_vm.this_domain.modified = false;
                                    }

                                    stringify_stats(move_options_vm.this_domain.details);

                                    move_options_vm.move_email_category =
                                    move_options_vm.this_domain.move_options["email-accounts"] ||
                                    move_options_vm.this_domain.move_options["email-forwarders"] ||
                                    move_options_vm.this_domain.move_options["autoresponders"];

                                    // Disable the email section configure button if there is no email data to move
                                    move_options_vm.disable_email_button = (
                                        move_options_vm.this_domain.details.number_of_email_accounts +
                                    move_options_vm.this_domain.details.number_of_domain_forwarders +
                                    move_options_vm.this_domain.details.number_of_email_forwarders +
                                    move_options_vm.this_domain.details.number_of_autoresponders) === 0;

                                    move_options_vm.move_db_category = move_options_vm.this_domain.move_options.mysql_dbs.length || move_options_vm.this_domain.move_options.mysql_users.length;
                                    move_options_vm.copy_mysql_dbs = (move_options_vm.this_domain.move_options.db_move_type === "copy") ? true : false;

                                    move_options_vm.move_website_data = move_options_vm.this_domain.move_options["docroot"] ||
                                                                    move_options_vm.this_domain.move_options["custom-vhost-includes"] ||
                                                                    move_options_vm.this_domain.move_options["copy-installed-ssl-cert"];

                                    move_options_vm.move_subaccount_category = move_options_vm.this_domain.move_options["ftp-accounts"] ||
                                    move_options_vm.this_domain.move_options["webdisk-accounts"];

                                    move_options_vm.selected_dbs_message = move_options_vm.copy_mysql_dbs ? LOCALE.maketext("You selected the following [asis,MySQL] databases to copy:") : LOCALE.maketext("You selected the following [asis,MySQL] databases to move:");

                                    // get the count of databases and the account packages available for the current user
                                    return $q.all([
                                        Databases.getDatabases(move_options_vm.this_domain.owner),
                                        AccountPackages.listPackages(),
                                    ])
                                        .then(function(data) {
                                            move_options_vm.enable_db_button = Object.keys(data[0]).length > 0;
                                            move_options_vm.account_packages = data[1];

                                            for (var i = 0, len = move_options_vm.account_packages.length; i < len; i++) {
                                                if (move_options_vm.account_packages[i].name &&
                                                    move_options_vm.account_packages[i].name === move_options_vm.this_domain.account_settings.pkgname) {
                                                    move_options_vm.selected_package = move_options_vm.account_packages[i];
                                                }
                                            }

                                            // default to the first package if one has not been selected
                                            if (move_options_vm.this_domain.account_settings.pkgname === "") {
                                                move_options_vm.selected_package = move_options_vm.account_packages[0];
                                            }

                                            move_options_vm.sync_pkg_settings();
                                        })
                                        .catch(function(meta) {
                                            var len = meta.errors.length;
                                            if (len > 1) {
                                                growl.error(meta.reason);
                                            }
                                            for (var i = 0; i < len; i++) {
                                                growl.error(meta.errors[i]);
                                            }
                                        })
                                        .finally(function() {
                                            move_options_vm.ui.domain_exists = true;
                                        });
                                } else {
                                    move_options_vm.domain_name = $routeParams.addondomain;
                                    move_options_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                move_options_vm.ui.is_loading = false;
                            });
                    }

                    function stringify_stats(data) {
                        move_options_vm.stats.email = {
                            "accounts": LOCALE.maketext("[quant,_1,Email account,Email accounts]", data.number_of_email_accounts),
                            "forwarders": LOCALE.maketext("[quant,_1,Forwarder,Forwarders]", data.number_of_email_forwarders + data.number_of_domain_forwarders),
                            "autoresponders": LOCALE.maketext("[quant,_1,Autoresponder,Autoresponders]", data.number_of_autoresponders),
                        };
                    }

                    function change_defaults(data) {
                        if (data.details.number_of_email_accounts === 0) {
                            move_options_vm.this_domain.move_options["email-accounts"] = false;
                        }

                        var total_forwarders = data.details.number_of_domain_forwarders + data.details.number_of_email_forwarders;
                        if (total_forwarders === 0) {
                            move_options_vm.this_domain.move_options["email-forwarders"] = false;
                        }

                        if (data.details.number_of_autoresponders === 0) {
                            move_options_vm.this_domain.move_options["autoresponders"] = false;
                        }

                        move_options_vm.show_ssl_copy_option = move_options_vm.this_domain.details.has_ssl_cert_installed === 1;

                        move_options_vm.sync_pkg_settings();
                    }

                    move_options_vm.sync_pkg_settings = function() {
                        if (move_options_vm.this_domain.details.has_dedicated_ip === 1 || move_options_vm.has_dedicated_ip) {
                            move_options_vm.ip_addr_will_change = true;
                        } else {
                            move_options_vm.ip_addr_will_change = false;
                        }
                    };

                    move_options_vm.generate_username = function(domain) {

                        // we want to strip off the TLD, then replace the numbers, dots, and anything
                        // not an ascii character for the username
                        var username = domain
                            .replace(/^\d+/, "")
                            .replace(/\.[^.]+$/, "")
                            .replace(/[^A-Za-z0-9]/g, "")
                            .substr(0, defaultInfo.username_restrictions.maxLength);
                        move_options_vm.this_domain.account_settings.username = username.toLowerCase();
                    };

                    move_options_vm.disableSave = function(form) {
                        return (form.$dirty && form.$invalid) || move_options_vm.ui.is_conversion_started || !move_options_vm.account_packages.length;
                    };

                    move_options_vm.addDbPrefix = function(db) {
                        if (Databases.isPrefixingEnabled()) {
                            return Databases.addPrefixIfNeeded(db, move_options_vm.this_domain.account_settings.username);
                        }

                        return db;
                    };

                    // watch the value of the selected account package
                    $scope.$watch(function() {
                        return move_options_vm.selected_package;
                    }, function(newPkg, oldPkg) {

                        // if we have no data yet, then just return.
                        // newPkg being undefined happens on initial load
                        if (Object.keys(move_options_vm.this_domain).length === 0 ||
                        newPkg === void 0) {
                            return;
                        }

                        // if the new package is null, then give the default values
                        if (newPkg === null) {
                            move_options_vm.has_dedicated_ip = false;
                            move_options_vm.this_domain.account_settings.pkgname = "";
                        } else {

                            // we have a new selected package, so lets update the values.
                            move_options_vm.has_dedicated_ip = newPkg.IP === "y" ? true : false;
                            move_options_vm.this_domain.account_settings.pkgname = newPkg.name;
                        }

                        move_options_vm.sync_pkg_settings();
                    });

                    move_options_vm.startConversion = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        move_options_vm.this_domain.modified = true;

                        // add prefixes to the databases as the last step in case they change the username before submission
                        if (Databases.isPrefixingEnabled() && move_options_vm.this_domain.move_options.db_move_type === "copy") {
                            for (var j = 0, dblen = move_options_vm.this_domain.move_options.mysql_dbs.length; j < dblen; j++) {
                                var db = move_options_vm.this_domain.move_options.mysql_dbs[j];
                                db.new_name = Databases.addPrefix(db.new_name, move_options_vm.this_domain.account_settings.username);
                            }
                        }

                        return ConvertAddonData.beginConversion(move_options_vm.this_domain)
                            .then(function(data) {
                                growl.success(LOCALE.maketext("The system started the conversion process for “[_1]”.",
                                    move_options_vm.domain_name));
                                move_options_vm.ui.is_conversion_started = true;

                                // send the user to the conversion history page
                                // would be better to do to the conversion details
                                // page, but the job id is not available at this point

                                return $location.path("/history");
                            })
                            .catch(function(meta) {
                                var len = meta.errors.length;
                                if (len > 1) {
                                    growl.error(meta.reason);
                                }
                                for (var i = 0; i < len; i++) {
                                    growl.error(meta.errors[i]);
                                }

                                move_options_vm.ui.is_conversion_started = false;
                            });
                    };

                    move_options_vm.goToEditView = function(category) {
                        return $location.path("/convert/" + move_options_vm.domain_name + "/migrations/edit/" + category);
                    };

                    move_options_vm.goToMain = function() {

                        // reset the account settings
                        move_options_vm.this_domain.account_settings = {};
                        return $location.path("/main");
                    };

                    init();
                },
            ]);

        return controller;
    }
);

/*
# views/docroot.js                                    Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/docroot',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/ConvertAddonData"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "docrootController",
            ["$anchorScroll", "$location", "$routeParams", "growl", "ConvertAddonData",
                function($anchorScroll, $location, $routeParams, growl, ConvertAddonData) {

                    var docroot = this;

                    docroot.loading = true;

                    docroot.moveIt = false;
                    docroot.moveVhostIncludes = false;
                    docroot.copySSLCert = false;
                    docroot.sslCertInstalled = false;
                    docroot.addonDomain = "";
                    docroot.domainData = {};
                    docroot.noSSLCertTooltip = LOCALE.maketext("The domain does not have an [asis,SSL] certificate installed.");

                    docroot.load = function() {
                        return ConvertAddonData.getAddonDomainDetails(docroot.addonDomain)
                            .then(
                                function(result) {
                                    docroot.moveIt = result.move_options.docroot;
                                    docroot.moveVhostIncludes = result.move_options["custom-vhost-includes"];
                                    docroot.sslCertInstalled = result.details["has_ssl_cert_installed"] === 1 ? true : false;
                                    docroot.copySSLCert = result.move_options["copy-installed-ssl-cert"] && docroot.sslCertInstalled;
                                    docroot.domainData = result;
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(
                                function() {
                                    docroot.loading = false;
                                }
                            );
                    };

                    docroot.goToOverview = function() {
                        return $location.path("/convert/" + docroot.addonDomain + "/migrations");
                    };

                    docroot.save = function() {
                        docroot.domainData.modified = true;
                        docroot.domainData.move_options.docroot = docroot.moveIt;
                        docroot.domainData.move_options["custom-vhost-includes"] = docroot.moveVhostIncludes;
                        docroot.domainData.move_options["copy-installed-ssl-cert"] = docroot.copySSLCert;
                        docroot.goToOverview();
                    };

                    docroot.cancel = function() {
                        docroot.goToOverview();
                    };

                    docroot.init = function() {
                        docroot.addonDomain = $routeParams.addondomain;
                        docroot.load();
                    };

                    docroot.init();
                }
            ]);

        return controller;
    }
);

/*
# views/dns.js                                    Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/dns',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/ConvertAddonData"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "dnsSelectionController",
            ["$anchorScroll", "$location", "$routeParams", "growl", "ConvertAddonData",
                function($anchorScroll, $location, $routeParams, growl, ConvertAddonData) {

                    var dns = this;

                    dns.loading = true;

                    dns.moveIt = true;
                    dns.addonDomain = "";
                    dns.domainData = {};

                    dns.load = function() {
                        return ConvertAddonData.getAddonDomainDetails(dns.addonDomain)
                            .then(
                                function(result) {
                                    dns.moveIt = result.move_options["custom-dns-records"];
                                    dns.domainData = result;
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(
                                function() {
                                    dns.loading = false;
                                }
                            );
                    };

                    dns.goToOverview = function() {
                        return $location.path("/convert/" + dns.addonDomain + "/migrations");
                    };

                    dns.save = function() {
                        dns.domainData.modified = true;
                        dns.domainData.move_options["custom-dns-records"] = dns.moveIt;
                        dns.goToOverview();
                    };

                    dns.cancel = function() {
                        dns.goToOverview();
                    };

                    dns.init = function() {
                        dns.addonDomain = $routeParams.addondomain;
                        dns.load();
                    };

                    dns.init();
                }
            ]);

        return controller;
    }
);

/*
# views/email_options.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/email_options',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/ConvertAddonData"
    ],
    function(angular, LOCALE) {

        var app = angular.module("App");

        var controller = app.controller(
            "emailSelectionController",
            ["$scope", "$q", "$location", "$routeParams", "ConvertAddonData",
                function($scope, $q, $location, $routeParams, ConvertAddonData) {
                    var email_selection_vm = this;

                    email_selection_vm.ui = {};
                    email_selection_vm.ui.is_loading = false;
                    email_selection_vm.ui.domain_exists = false;
                    email_selection_vm.this_domain = {};

                    email_selection_vm.stats = {};

                    email_selection_vm.noEmailAccountsTooltip = LOCALE.maketext("The domain does not have email accounts.");
                    email_selection_vm.noAutorespondersTooltip = LOCALE.maketext("The domain does not have autoresponders.");
                    email_selection_vm.noForwardersTooltip = LOCALE.maketext("The domain does not have email forwarders.");

                    // initialize the view
                    function init() {
                        email_selection_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomain($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    email_selection_vm.domain_name = data.addon_domain;
                                    email_selection_vm.this_domain = data;

                                    if (data.details.number_of_email_forwarders === void 0) {
                                        data.details.number_of_email_forwarders = 0;
                                    }

                                    if (data.details.number_of_domain_forwarders === void 0) {
                                        data.details.number_of_domain_forwarders = 0;
                                    }

                                    if (data.details.number_of_email_accounts === void 0) {
                                        data.details.number_of_email_accounts = 0;
                                    }

                                    if (data.details.number_of_autoresponders === void 0) {
                                        data.details.number_of_autoresponders = 0;
                                    }

                                    email_selection_vm.email_accounts = data.move_options["email-accounts"];
                                    email_selection_vm.email_forwarders = data.move_options["email-forwarders"];
                                    email_selection_vm.autoresponders = data.move_options["autoresponders"];

                                    // disable webmail data if there are no email accounts
                                    if (data.details.number_of_email_accounts === 0) {
                                        email_selection_vm.webmail_data = false;
                                    }

                                    stringify_stats(email_selection_vm.this_domain.details);

                                    email_selection_vm.total_forwarders = data.details.number_of_email_forwarders +
                                    data.details.number_of_domain_forwarders;
                                    email_selection_vm.ui.domain_exists = true;
                                } else {
                                    email_selection_vm.domain_name = $routeParams.addondomain;
                                    email_selection_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                email_selection_vm.ui.is_loading = false;
                            });
                    }

                    function stringify_stats(data) {
                        email_selection_vm.stats = {
                            "accounts": LOCALE.maketext("[quant,_1,Email account,Email accounts]", data.number_of_email_accounts),
                            "emailForwarders": LOCALE.maketext("[quant,_1,Email forwarder,Email forwarders]", data.number_of_email_forwarders),
                            "domainForwarders": LOCALE.maketext("[quant,_1,Domain forwarder,Domain forwarders]", data.number_of_domain_forwarders),
                            "autoresponders": LOCALE.maketext("[quant,_1,Autoresponder,Autoresponders]", data.number_of_autoresponders)
                        };
                    }

                    email_selection_vm.saveOptions = function() {
                        email_selection_vm.this_domain.modified = true;
                        email_selection_vm.this_domain.move_options["email-accounts"] = email_selection_vm.email_accounts;
                        email_selection_vm.this_domain.move_options["email-forwarders"] = email_selection_vm.email_forwarders;
                        email_selection_vm.this_domain.move_options["autoresponders"] = email_selection_vm.autoresponders;
                        return $location.path("/convert/" + email_selection_vm.domain_name + "/migrations");
                    };

                    email_selection_vm.goBack = function() {
                        return $location.path("/convert/" + email_selection_vm.domain_name + "/migrations");
                    };

                    init();
                }
            ]);

        return controller;
    }
);

/*
# models/dynamic_table.js                         Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/models/dynamic_table',[
        "lodash",
        "cjt/util/locale",
    ],
    function(_, LOCALE) {

        /**
         * Creates a Dynamic Table object
         *
         * @class
         */
        function DynamicTable() {
            this.items = [];
            this.filteredList = this.items;
            this.selected = [];
            this.allDisplayedRowsSelected = false;
            this.filterFunction = void 0;

            this.meta = {
                sortBy: "",
                sortDirection: "asc",
                maxPages: 0,
                totalItems: this.items.length,
                pageNumber: 1,
                pageSize: 10,
                pageSizes: [10, 20, 50, 100],
                start: 0,
                limit: 10,
                filterValue: "",
            };
        }

        /**
         * Set the filter function to be used for searching the table
         *
         * @method loadData
         * @param {Array} data - an array of objects representing the data to display
         */
        DynamicTable.prototype.loadData = function(data) {
            this.items = data;

            for (var i = 0, len = this.items.length; i < len; i++) {

                // add a unique id to each piece of data
                this.items[i]._id = i;

                // initialize the selected array with the ids of selected items
                if (this.items[i].selected) {
                    this.selected.push(this.items[i]._id);
                }
            }
        };

        /**
         * Set the filter function to be used for searching the table
         *
         * @method setFilterFunction
         * @param {Function} func - a function that can be used to search the data
         * @note The function passed to this function must
         * - return a boolean
         * - accept the following args: an item object and the search text
         */
        DynamicTable.prototype.setFilterFunction = function(func) {
            if (_.isFunction(func)) {
                this.filterFunction = func;
            }
        };

        /**
         * Set the filter function to be used for searching the table
         *
         * @method setSort
         * @param {String} by - the field you want to sort on
         * @param {String} direction - the direction you want to sort, "asc" or "desc"
         */
        DynamicTable.prototype.setSort = function(by, direction) {
            if (by !== void 0) {
                this.meta.sortBy = by;
            }

            if (direction !== void 0) {
                this.meta.sortDirection = direction;
            }
        };

        /**
         * Get the table metadata
         *
         * @method getMetadata
         * @return {Object} The metadata for the table
         */
        DynamicTable.prototype.getMetadata = function() {
            return this.meta;
        };

        /**
         * Get the table data
         *
         * @method getList
         * @return {Array} The table data
         */
        DynamicTable.prototype.getList = function() {
            return this.filteredList;
        };

        /**
         * Get the table data that is selected
         *
         * @method getSelectedList
         * @return {Array} The table data that is selected
         */
        DynamicTable.prototype.getSelectedList = function() {
            return this.items.filter(function(item) {
                return item.selected;
            });
        };

        /**
         * Determine if all the filtered table rows are selected
         *
         * @method areAllDisplayedRowsSelected
         * @return {Boolean}
         */
        DynamicTable.prototype.areAllDisplayedRowsSelected = function() {
            return this.allDisplayedRowsSelected;
        };

        /**
         * Get the total selected rows in the table
         *
         * @method getTotalRowsSelected
         * @return {Number} total of selected rows in the table
         */
        DynamicTable.prototype.getTotalRowsSelected = function() {
            return this.selected.length;
        };

        /**
         * Select all items for a single page of data in the table
         *
         * @method selectAllDisplayed
         * @param {Boolean} toggle - determines whether to select or unselect all
         * displayed items
         */
        DynamicTable.prototype.selectAllDisplayed = function(toggle) {
            if (toggle) {

                // Select the rows if they were previously selected on this page.
                for (var i = 0, filteredLen = this.filteredList.length; i < filteredLen; i++) {
                    var item = this.filteredList[i];
                    item.selected = true;

                    // make sure this item is not already in the list
                    if (this.selected.indexOf(item._id) !== -1) {
                        continue;
                    }

                    this.selected.push(item._id);
                }
            } else {

                // Extract the unselected items and remove them from the selected collection.
                var unselected = this.filteredList.map(function(item) {
                    item.selected = false;
                    return item._id;
                });

                this.selected = _.difference(this.selected, unselected);
            }

            this.allDisplayedRowsSelected = toggle;
        };

        /**
         * Select an item on the current page.
         *
         * @method selectItem
         * @param {Object} item - the item that we want to mark as selected.
         * NOTE: the item must have the selected property set to true before
         * passing it to this function
         */
        DynamicTable.prototype.selectItem = function(item) {
            if (typeof item !== "undefined") {
                if (item.selected) {

                    // make sure this item is not already in the list
                    if (this.selected.indexOf(item._id) !== -1) {
                        return;
                    }

                    this.selected.push(item._id);

                    // Sync 'Select All' checkbox status when a new selction/unselection
                    // is made.
                    this.allDisplayedRowsSelected = this.filteredList.every(function(thisitem) {
                        return thisitem.selected;
                    });
                } else {
                    this.selected = this.selected.filter(function(thisid) {
                        return thisid !== item._id;
                    });

                    // Unselect Select All checkbox.
                    this.allDisplayedRowsSelected = false;
                }
            }
        };

        /**
         * Clear all selections for all pages.
         *
         * @method clearAllSelections
         */
        DynamicTable.prototype.clearAllSelections = function() {
            this.selected = [];

            for (var i = 0, len = this.items.length; i < len; i++) {
                var item = this.items[i];
                item.selected = false;
            }

            this.allDisplayedRowsSelected = false;
        };

        /**
         * Clear the entire table.
         *
         * @method clear
         */
        DynamicTable.prototype.clear = function() {
            this.items = [];
            this.selected = [];
            this.allDisplayedRowsSelected = false;
            this.filteredList = this.populate();
        };

        /**
         * Populate the table with data accounting for filtering, sorting, and paging
         *
         * @method populate
         * @return {Array} the table data
         */
        DynamicTable.prototype.populate = function() {
            var filtered = [];
            var self = this;

            // filter list based on search text
            if (this.meta.filterValue !== "" && _.isFunction(this.filterFunction)) {
                filtered = this.items.filter(function(item) {
                    return self.filterFunction(item, self.meta.filterValue);
                });
            } else {
                filtered = this.items;
            }

            // sort the filtered list
            if (this.meta.sortDirection !== "" && this.meta.sortBy !== "") {
                filtered = _.orderBy(filtered, [this.meta.sortBy], [this.meta.sortDirection]);
            }

            // update the total items after search
            this.meta.totalItems = filtered.length;

            // filter list based on page size and pagination and handle the case
            // where the page size is "ALL" (-1)
            if (this.meta.totalItems > _.min(this.meta.pageSizes) ) {
                var start = (this.meta.pageNumber - 1) * this.meta.pageSize;
                var limit = this.meta.pageNumber * this.meta.pageSize;

                filtered = _.slice(filtered, start, limit);

                this.meta.start = start + 1;
                this.meta.limit = start + filtered.length;
            } else {
                if (filtered.length === 0) {
                    this.meta.start = 0;
                } else {
                    this.meta.start = 1;
                }

                this.meta.limit = filtered.length;
            }

            var countNonSelected = 0;
            for (var i = 0, filteredLen = filtered.length; i < filteredLen; i++) {
                var item = filtered[i];

                // Select the rows if they were previously selected on this page.
                if (this.selected.indexOf(item._id) !== -1) {
                    item.selected = true;
                } else {
                    item.selected = false;
                    countNonSelected++;
                }
            }

            this.filteredList = filtered;

            // Clear the 'Select All' checkbox if at least one row is not selected.
            this.allDisplayedRowsSelected = (filtered.length > 0) && (countNonSelected === 0);

            return filtered;
        };

        /**
         * Create a localized message for the table stats
         *
         * @method paginationMessage
         * @return {String}
         */
        DynamicTable.prototype.paginationMessage = function() {
            return LOCALE.maketext("Displaying [numf,_1] to [numf,_2] out of [quant,_3,item,items]", this.meta.start, this.meta.limit, this.meta.totalItems);
        };

        return DynamicTable;
    }
);

/*
# convert_addon_to_account/directives/db_name_validators.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                                      All rights reserved.
# copyright@cpanel.net                                                    http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* global define: false, CPANEL: false */
/* --------------------------*/

define('app/directives/db_name_validators',[
    "angular",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory",
    "app/services/Databases"
],
function(angular, validationUtils, LOCALE, validateFactory, Databases) {
    var validators = {

        /**
             * Validate a MySQL Database Name
             * NOTE: This method depends on the old cjt/sql.js file being loaded
             *
             * @method mysqlDbName
             * @param {string} val - the value to be validated
             * @return a validation result object
             */
        mysqlDbName: function(val) {
            var result = validationUtils.initializeValidationResult();

            try {
                CPANEL.sql.verify_mysql_database_name(val);
                result.isValid = true;
            } catch (error) {
                result.isValid = false;
                result.add("db", error);
            }

            return result;
        },

        /**
             * Validate a Postgres Database Name
             * NOTE: This method depends on the old cjt/sql.js file being loaded
             *
             * @method postrgresDbName
             * @param {string} val - the value to be validated
             * @return a validation result object
             */
        postgresqlDbName: function(val) {
            var result = validationUtils.initializeValidationResult();

            try {
                CPANEL.sql.verify_postgresql_database_name(val);
                result.isValid = true;
            } catch (error) {
                result.isValid = false;
                result.add("db", error);
            }

            return result;
        }
    };

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory", "Databases",
        function(validatorFactory, Databases) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "dbNameValidators",
        description: "Validation directives for db names.",
        version: 11.56,
    };
}
);

/*
# views/db_options.js                             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, CPANEL: false */

define(
    'app/views/db_options',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/models/dynamic_table",
        "cjt/decorators/growlDecorator",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "app/services/ConvertAddonData",
        "app/services/Databases",
        "app/directives/db_name_validators"
    ],
    function(angular, _, LOCALE, DynamicTable) {

        var app = angular.module("App");

        var controller = app.controller(
            "databaseSelectionController",
            ["$q", "$location", "$routeParams", "growl", "ConvertAddonData", "Databases", "$anchorScroll",
                function($q, $location, $routeParams, growl, ConvertAddonData, Databases, $anchorScroll) {
                    var db_selection_vm = this;

                    db_selection_vm.ui = {};
                    db_selection_vm.ui.is_loading = false;
                    db_selection_vm.ui.domain_exists = false;
                    db_selection_vm.this_domain = {};

                    db_selection_vm.is_prefixing_enabled = void 0;
                    db_selection_vm.move_type = "move";

                    // This function exists in the old cjt/sql.js file
                    db_selection_vm.database_name_max_length = CPANEL.sql.get_name_length_limit("mysql", "database");

                    var db_table = new DynamicTable();
                    db_table.setSort("db_name");

                    var user_table = new DynamicTable();
                    user_table.setSort("user_name");

                    function searchDbsFunction(item, searchText) {
                        return item.db_name.indexOf(searchText) !== -1;
                    }
                    db_table.setFilterFunction(searchDbsFunction);

                    function searchUsersFunction(item, searchText) {
                        return item.user_name.indexOf(searchText) !== -1;
                    }
                    user_table.setFilterFunction(searchUsersFunction);

                    db_selection_vm.dbs = {
                        "checkDropdownOpen": false,
                        "allRowsSelected": db_table.areAllDisplayedRowsSelected(),
                        "meta": db_table.getMetadata(),
                        "filteredList": db_table.getList(),
                        "totalSelected": db_table.getTotalRowsSelected(),
                        "paginationMessage": db_table.paginationMessage,
                        "fetch": function() {
                            db_selection_vm.dbs.filteredList = db_table.populate();
                            db_selection_vm.dbs.allRowsSelected = db_table.areAllDisplayedRowsSelected();
                            db_selection_vm.dbs.totalSelected = db_table.getTotalRowsSelected();
                        },
                        "sortList": function() {
                            db_selection_vm.dbs.fetch();
                        },
                        "selectPage": function() {
                            db_selection_vm.dbs.fetch();
                        },
                        "selectPageSize": function() {
                            db_selection_vm.dbs.fetch();
                        },
                        "searchList": function() {
                            db_selection_vm.dbs.fetch();
                        },
                        "selectAll": function(model) {
                            db_table.selectAllDisplayed(model);
                            db_selection_vm.dbs.fetch();
                            db_selection_vm.dbs.allRowsSelected = db_table.areAllDisplayedRowsSelected();
                            db_selection_vm.dbs.totalSelected = db_table.getTotalRowsSelected();
                        },
                        "selectDb": function(db) {
                            db_table.selectItem(db);
                            db_selection_vm.dbs.allRowsSelected = db_table.areAllDisplayedRowsSelected();
                            db_selection_vm.dbs.totalSelected = db_table.getTotalRowsSelected();
                        },
                        "clearAllSelections": function(event) {
                            event.preventDefault();
                            event.stopPropagation();

                            db_table.clearAllSelections();
                            db_selection_vm.dbs.checkDropdownOpen = false;
                            db_selection_vm.dbs.allRowsSelected = db_table.areAllDisplayedRowsSelected();
                            db_selection_vm.dbs.totalSelected = db_table.getTotalRowsSelected();
                        }
                    };

                    db_selection_vm.users = {
                        "checkDropdownOpen": false,
                        "allRowsSelected": user_table.areAllDisplayedRowsSelected(),
                        "meta": user_table.getMetadata(),
                        "filteredList": user_table.getList(),
                        "totalSelected": user_table.getTotalRowsSelected(),
                        "paginationMessage": user_table.paginationMessage,
                        "fetch": function() {
                            db_selection_vm.users.filteredList = user_table.populate();
                            db_selection_vm.users.allRowsSelected = user_table.areAllDisplayedRowsSelected();
                            db_selection_vm.users.totalSelected = user_table.getTotalRowsSelected();
                        },
                        "sortList": function() {
                            db_selection_vm.users.fetch();
                        },
                        "selectPage": function() {
                            db_selection_vm.users.fetch();
                        },
                        "selectPageSize": function() {
                            db_selection_vm.users.fetch();
                        },
                        "searchList": function() {
                            db_selection_vm.users.fetch();
                        },
                        "selectAll": function(model) {
                            user_table.selectAllDisplayed(model);
                            db_selection_vm.users.fetch();
                            db_selection_vm.users.allRowsSelected = user_table.areAllDisplayedRowsSelected();
                            db_selection_vm.users.totalSelected = user_table.getTotalRowsSelected();
                        },
                        "selectUser": function(db) {
                            user_table.selectItem(db);
                            db_selection_vm.users.allRowsSelected = user_table.areAllDisplayedRowsSelected();
                            db_selection_vm.users.totalSelected = user_table.getTotalRowsSelected();
                        },
                        "clearAllSelections": function(event) {
                            event.preventDefault();
                            event.stopPropagation();

                            user_table.clearAllSelections();
                            db_selection_vm.users.checkDropdownOpen = false;
                            db_selection_vm.users.allRowsSelected = user_table.areAllDisplayedRowsSelected();
                            db_selection_vm.users.totalSelected = user_table.getTotalRowsSelected();
                        }
                    };

                    function convertDBObjectToList(dbs) {
                        var existing_db;
                        var has_selections = db_selection_vm.this_domain.move_options["mysql_dbs"] &&
                        db_selection_vm.this_domain.move_options["mysql_dbs"].length > 0;
                        var prefix = Databases.createPrefix(db_selection_vm.this_domain.account_settings.username);
                        var data = [];
                        for (var db in dbs) {
                            if (dbs.hasOwnProperty(db)) {

                            // If the user had already selected this database to move,
                            // we should mark it as selected
                                if (has_selections &&
                                (existing_db = _.find(db_selection_vm.this_domain.move_options.mysql_dbs, { "name": db })) !== void 0) {
                                    data.push({
                                        "db_name": db,
                                        "db_users": dbs[db],
                                        "selected": true,
                                        "db_new_name": existing_db.new_name,
                                        "db_prefix": prefix
                                    });
                                } else {
                                    data.push({
                                        "db_name": db,
                                        "db_users": dbs[db],
                                        "selected": false,
                                        "db_new_name": "",
                                        "db_prefix": prefix
                                    });
                                }
                                existing_db = void 0;
                            }
                        }
                        db_table.loadData(data);
                    }

                    function convertUsersObjectToList(users) {
                        var existing_user;
                        var has_selections = db_selection_vm.this_domain.move_options["mysql_users"] &&
                        db_selection_vm.this_domain.move_options["mysql_users"].length > 0;
                        var data = [];
                        for (var user in users) {
                            if (users.hasOwnProperty(user)) {

                            // If the user had already selected this user to move,
                            // we should mark it as selected
                                if (has_selections &&
                                (existing_user = _.find(db_selection_vm.this_domain.move_options.mysql_users, { "name": user })) !== void 0) {
                                    data.push({
                                        "user_name": user,
                                        "user_databases": users[user],
                                        "selected": true
                                    });
                                } else {
                                    data.push({
                                        "user_name": user,
                                        "user_databases": users[user],
                                        "selected": false
                                    });
                                }
                                existing_user = void 0;
                            }
                        }
                        user_table.loadData(data);
                    }

                    db_selection_vm.disableSave = function(form) {
                        return (form.$dirty && form.$invalid);
                    };

                    db_selection_vm.saveOptions = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        db_selection_vm.this_domain.modified = true;

                        var selected_dbs = db_table.getSelectedList();

                        db_selection_vm.this_domain.move_options.db_move_type = db_selection_vm.move_type;
                        db_selection_vm.this_domain.move_options["mysql_dbs"] = selected_dbs.map(function(item) {
                            return {
                                "name": item.db_name,
                                "new_name": item.db_new_name
                            };
                        });

                        if (db_selection_vm.this_domain.move_options.db_move_type === "move") {
                            var selected_users = user_table.getSelectedList();
                            db_selection_vm.this_domain.move_options["mysql_users"] = selected_users.map(function(item) {
                                return {
                                    "name": item.user_name,
                                };
                            });
                        } else {
                            db_selection_vm.this_domain.move_options["mysql_users"] = [];
                        }

                        return $location.path("/convert/" + db_selection_vm.domain_name + "/migrations");
                    };

                    db_selection_vm.goBack = function() {
                        return $location.path("/convert/" + db_selection_vm.domain_name + "/migrations");
                    };

                    db_selection_vm.init = function() {
                        db_selection_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomain($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    db_selection_vm.domain_name = data.addon_domain;
                                    db_selection_vm.this_domain = data;

                                    if (data.move_options.db_move_type) {
                                        db_selection_vm.move_type = data.move_options.db_move_type;
                                    }

                                    return Databases.getDatabases(db_selection_vm.this_domain.owner)
                                        .then(function(data) {
                                            convertDBObjectToList(data);
                                            convertUsersObjectToList(Databases.getUsers());
                                            db_selection_vm.is_prefixing_enabled = Databases.isPrefixingEnabled();
                                            if (db_selection_vm.is_prefixing_enabled) {
                                                db_selection_vm.database_name_max_length -= Databases.getPrefixLength();
                                            }
                                            db_selection_vm.dbs.fetch();
                                            db_selection_vm.users.fetch();
                                            db_selection_vm.ui.domain_exists = true;
                                        })
                                        .catch(function(meta) {
                                            var len = meta.errors.length;
                                            if (len > 1) {
                                                growl.error(meta.reason);
                                            }
                                            for (var i = 0; i < len; i++) {
                                                growl.error(meta.errors[i]);
                                            }
                                        });
                                } else {
                                    db_selection_vm.domain_name = $routeParams.addondomain;
                                    db_selection_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                db_selection_vm.ui.is_loading = false;
                                $location.hash("pageContainer");
                                $anchorScroll();
                            });
                    };

                    db_selection_vm.init();
                }
            ]);

        return controller;
    }
);

/*
# views/conversion_detail.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/conversion_detail',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/conversion_history"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "conversionDetailController",
            ["$anchorScroll", "$location", "$routeParams", "growl", "ConversionHistory", "$timeout",
                function($anchorScroll, $location, $routeParams, growl, ConversionHistory, $timeout) {

                    var detail = this;

                    detail.loading = true;

                    detail.jobId = 0;

                    detail.conversionData = {};
                    detail.progressBarType = "info";
                    detail.currentProgressMessage = "";

                    detail.splitWarnings = function(warnings) {
                        if (warnings) {
                            return warnings.split("\n");
                        }
                        return null;
                    };

                    detail.viewHistory = function() {
                        $location.path("/history/");
                    };

                    detail.viewAddons = function() {
                        $location.path("/main");
                    };

                    detail.updateSteps = function() {
                        return ConversionHistory.getDetails(detail.jobId, detail.currentStep)
                            .then(
                                function(result) {

                                    // check to see if local copy of conversion data is
                                    // populated. if not, put the results of the getDatails
                                    // call there
                                    if (!detail.conversionData.hasOwnProperty("domain")) {

                                        // make a local copy of the data so the
                                        // ui is properly synchronized
                                        for (var prop in result) {

                                            if (result.hasOwnProperty(prop)) {
                                                if (prop === "steps") {
                                                    continue;
                                                }
                                                detail.conversionData[prop] = result[prop];
                                            }
                                        }

                                        detail.conversionData.steps = result.steps.slice();

                                        if (detail.conversionData.job_status === "INPROGRESS") {
                                            detail.currentProgressMessage = detail.conversionData.steps[detail.conversionData.steps.length - 1].step_name;
                                            detail.progressBarType = "info";
                                            return $timeout(function() {
                                                return detail.updateSteps();
                                            }, 2000);
                                        } else if (detail.conversionData.job_status === "DONE") {
                                            detail.currentProgressMessage = LOCALE.maketext("Conversion Completed");
                                            detail.progressBarType = "success";
                                        } else {
                                            detail.currentProgressMessage = LOCALE.maketext("Conversion Failed");
                                            detail.progressBarType = "danger";
                                        }
                                    } else { // otherwise, add any new steps to the local copy

                                        // if the current list of steps is shorter than the new list
                                        // add the new steps to the end of the list
                                        var currentStepCount = detail.conversionData.steps.length;
                                        var newStepCount = result.steps.length;

                                        if ( currentStepCount < newStepCount) {

                                            // update last step with new status and warnings, if any
                                            detail.conversionData.steps[currentStepCount - 1].status = result.steps[currentStepCount - 1].status;
                                            if (result.steps[currentStepCount - 1].warnings) {
                                                detail.conversionData.steps[currentStepCount - 1].warnings = result.steps[currentStepCount - 1].warnings;
                                            }

                                            // add any new steps after the updated last step
                                            var newSteps = result.steps.slice(currentStepCount);
                                            detail.conversionData.steps = detail.conversionData.steps.concat(newSteps);

                                            // update the status message to the new last step name
                                            if (result.job_status === "FAILED") {
                                                detail.progressBarType = "danger";
                                            } else if (result.job_status === "DONE") {
                                                detail.progressBarType = "success";
                                            } else {
                                                detail.progressBarType = "info";
                                            }

                                            detail.currentProgressMessage = detail.conversionData.steps[detail.conversionData.steps.length - 1].step_name;
                                        }

                                        if (!result.job_end_time || result.steps[newStepCount - 1].status === "INPROGRESS") {

                                            // still in progress--schedule the next check
                                            // schedule at least one final check in any case
                                            return $timeout(function() {
                                                return detail.updateSteps();
                                            }, 2000);
                                        } else {
                                            detail.conversionData.job_status = result.job_status;
                                            detail.conversionData.job_end_time = result.job_end_time;

                                            if (detail.conversionData.job_status === "DONE") {
                                                detail.currentProgressMessage = LOCALE.maketext("Conversion Completed");
                                                detail.progressBarType = "success";
                                            } else if (detail.conversionData.job_status === "FAILED") {
                                                detail.currentProgressMessage = LOCALE.maketext("Conversion Failed");
                                                detail.progressBarType = "danger";
                                            }
                                        }
                                    }

                                }, function(error) {
                                    growl.error(error);
                                }
                            );
                    };

                    detail.load = function() {
                        detail.loading = true;
                        detail.updateSteps()
                            .finally(
                                function() {
                                    detail.loading = false;
                                }
                            );
                    };

                    detail.goToHistory = function() {
                        return $location.path("/history");
                    };

                    detail.init = function() {
                        detail.jobId = $routeParams.jobid;
                        detail.load();
                    };

                    detail.init();
                }
            ]);

        return controller;
    }
);

/*
# views/subaccounts.js                            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/subaccounts',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/ConvertAddonData"
    ],
    function(angular, LOCALE) {

        var app = angular.module("App");

        var controller = app.controller(
            "subaccountSelectionController",
            ["$scope", "$q", "$location", "$routeParams", "ConvertAddonData",
                function($scope, $q, $location, $routeParams, ConvertAddonData) {
                    var sub_vm = this;

                    sub_vm.ui = {};
                    sub_vm.ui.is_loading = false;
                    sub_vm.ui.domain_exists = false;
                    sub_vm.this_domain = {};

                    sub_vm.stats = {};

                    function init() {
                        sub_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomain($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    sub_vm.domain_name = data.addon_domain;
                                    sub_vm.this_domain = data;

                                    sub_vm.ftp_accounts = data.move_options["ftp-accounts"];
                                    sub_vm.webdisk_accounts = data.move_options["webdisk-accounts"];

                                    sub_vm.ui.domain_exists = true;
                                } else {
                                    sub_vm.domain_name = $routeParams.addondomain;
                                    sub_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                sub_vm.ui.is_loading = false;
                            });
                    }

                    sub_vm.saveOptions = function() {
                        sub_vm.this_domain.modified = true;
                        sub_vm.this_domain.move_options["ftp-accounts"] = sub_vm.ftp_accounts;
                        sub_vm.this_domain.move_options["webdisk-accounts"] = sub_vm.webdisk_accounts;
                        return $location.path("/convert/" + sub_vm.domain_name + "/migrations");
                    };

                    sub_vm.goBack = function() {
                        return $location.path("/convert/" + sub_vm.domain_name + "/migrations");
                    };

                    init();
                }
            ]);

        return controller;
    }
);

/*
# convert_addon_to_account/directives/job_status.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define(
    'app/directives/job_status',[
        "angular",
        "cjt/util/locale",
        "cjt/core",
    ],
    function(angular, LOCALE, CJT) {

        var app = angular.module("App");
        app.directive("jobStatus",
            [
                function() {
                    var TEMPLATE_PATH = "directives/job_status.phtml";
                    var RELATIVE_PATH = "templates/convert_addon_to_account/" + TEMPLATE_PATH;
                    var IN_PROGRESS_TEXT = LOCALE.maketext("In Progress");
                    var DONE_TEXT = LOCALE.maketext("Done");
                    var FAILED_TEXT = LOCALE.maketext("Failed");
                    var DEFAULT_TEXT = "";

                    function update_status(status, scope) {
                        scope.success = false;
                        scope.error = false;
                        scope.pending = false;

                        if (status === "INPROGRESS") {
                            scope.label = IN_PROGRESS_TEXT;
                            scope.pending = true;
                        } else if (status === "DONE") {
                            scope.label = DONE_TEXT;
                            scope.success = true;
                        } else if (status === "FAILED") {
                            scope.label = FAILED_TEXT;
                            scope.error = true;
                        } else {
                            scope.label = DEFAULT_TEXT;
                        }
                    }

                    return {
                        replace: true,
                        require: "ngModel",
                        restrict: "E",
                        scope: {
                            ngModel: "=",
                        },
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        link: function(scope, element, attrs) {
                            update_status(scope.ngModel, scope);

                            scope.$watch("ngModel", function(newValue, oldValue) {
                                if (newValue && newValue !== oldValue) {
                                    update_status(newValue, scope);
                                }
                            });
                        }
                    };
                }
            ]);
    }
);

/*
# convert_addon_to_account/views/history.js       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* eslint camelcase: "off" */

define(
    'app/views/history',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/models/dynamic_table",
        "app/services/conversion_history",
        "app/filters/local_datetime_filter",
        "app/directives/job_status",
        "cjt/decorators/growlDecorator",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective"
    ],
    function(angular, _, LOCALE, DynamicTable, ConversionHistory) {
        "use strict";

        var app = angular.module("App");

        var controller = app.controller(
            "historyController",
            ["$location", "growl", "ConversionHistory", "$timeout", "$scope",
                function($location, growl, ConversionHistory, $timeout, $scope) {
                    var history_vm = this;

                    history_vm.ui = {};
                    history_vm.ui.is_loading = false;
                    history_vm.in_progress = {};
                    history_vm.in_progress_timer = null;

                    var conversion_table = new DynamicTable();
                    conversion_table.setSort("start_time");

                    function searchConversionsFunction(item, searchText) {
                        return item.domain.indexOf(searchText) !== -1;
                    }
                    conversion_table.setFilterFunction(searchConversionsFunction);

                    history_vm.conversions = {
                        "meta": conversion_table.getMetadata(),
                        "filteredList": conversion_table.getList(),
                        "paginationMessage": conversion_table.paginationMessage,
                        "fetch": function() {
                            history_vm.conversions.filteredList = conversion_table.populate();
                        },
                        "sortList": function() {
                            history_vm.conversions.fetch();
                        },
                        "selectPage": function() {
                            history_vm.conversions.fetch();
                        },
                        "selectPageSize": function() {
                            history_vm.conversions.fetch();
                        },
                        "searchList": function() {
                            history_vm.conversions.fetch();
                        }
                    };

                    history.clearSearch = function(event) {
                        if (event.keyCode === 27) {
                            history.conversions.meta.filterValue = "";
                            history.conversions.searchList();
                        }
                    };

                    // sort the status in descending order to make the
                    // most recent ones show at the top
                    history_vm.conversions.meta.sortDirection = "desc";

                    history_vm.updateStatusFor = function(job_ids) {
                        return ConversionHistory.getJobStatus(job_ids)
                            .then(function(data) {
                                for (var job in data) {
                                    if (history_vm.in_progress[job] !== void 0 &&
                                    data[job].job_status !== history_vm.in_progress[job].status) {
                                        history_vm.in_progress[job].status = data[job].job_status;

                                        if (data[job].job_status !== "INPROGRESS") {
                                            history_vm.in_progress[job].end_time = data[job].job_end_time;
                                            var this_domain = history_vm.in_progress[job].domain;
                                            if (data[job].job_status === "FAILED") {
                                                growl.error(LOCALE.maketext("The conversion of the domain “[_1]” failed.", _.escape(this_domain)));
                                            } else {
                                                growl.info(LOCALE.maketext("The conversion of the domain “[_1]” succeeded.", _.escape(this_domain)));
                                            }
                                            delete history_vm.in_progress[job];
                                        }
                                    }
                                }

                                if (Object.keys(history_vm.in_progress).length !== 0) {
                                    history_vm.in_progress_timer = $timeout(function() {
                                        history_vm.updateStatusFor(job_ids);
                                    }, 1000);
                                }
                            });
                    };

                    history_vm.goToDetailsView = function(job_id) {
                        return $location.path("/history/" + job_id + "/detail");
                    };

                    history_vm.viewAddons = function() {
                        $location.path("/main");
                    };

                    history_vm.init = function() {
                        history_vm.ui.is_loading = true;

                        ConversionHistory.load()
                            .then(function(data) {
                                conversion_table.loadData(data);
                                history_vm.conversions.fetch();

                                // iterate through the list of
                                // jobs and find the ones that are
                                // in progress
                                var totalJobs = data.length;
                                var i = 0;

                                for (; i < totalJobs; i++) {
                                    if (data[i].status === "INPROGRESS") {
                                        history_vm.in_progress[data[i].job_id] = data[i];
                                    }
                                }

                                var job_ids = Object.keys(history_vm.in_progress);

                                if (job_ids.length > 0) {
                                /* jshint -W083 */
                                    history_vm.in_progress_timer = $timeout( function() {
                                        history_vm.updateStatusFor(job_ids);
                                    }, 1000);
                                /* jshint +W083 */
                                }

                            })
                            .catch(function(meta) {
                                growl.error(meta.reason);
                            })
                            .finally(function() {
                                history_vm.ui.is_loading = false;
                            });
                    };

                    history_vm.clearInProgress = function() {
                        if (history_vm.in_progress_timer) {
                            $timeout.cancel(history_vm.in_progress_timer);
                            history_vm.in_progress_timer = null;
                        }
                        history_vm.in_progress = {};
                    };

                    history_vm.forceLoadList = function() {
                        conversion_table.clear();
                        history_vm.clearInProgress();
                        history_vm.init();
                    };

                    $scope.$on("$destroy", function() {
                        history_vm.clearInProgress();
                    });

                    history_vm.init();
                }
            ]);

        return controller;
    }
);

/*
# index.js                                        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, PAGE: false */
/* jshint -W100 */

define(
    'app/index',[
        "angular",
        "jquery",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "uiBootstrap"
    ],
    function(angular, $, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ngAnimate",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/services/pageDataService",
                    "app/services/ConvertAddonData",
                    "app/services/Databases",
                    "app/services/account_packages",
                    "app/services/conversion_history",
                    "app/filters/local_datetime_filter",
                    "app/views/main",
                    "app/views/move_options",
                    "app/views/docroot",
                    "app/views/dns",
                    "app/views/email_options",
                    "app/views/db_options",
                    "app/views/conversion_detail",
                    "app/views/subaccounts",
                    "app/views/history",
                    "app/directives/move_status",
                    "app/directives/job_status"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.firstLoad = {
                        addonList: true
                    };

                    // setup the defaults for the various services.
                    app.factory("defaultInfo", [
                        "pageDataService",
                        function(pageDataService) {
                            return pageDataService.prepareDefaultInfo(PAGE);
                        }
                    ]);

                    app.config([
                        "$routeProvider",
                        "$anchorScrollProvider",
                        function($routeProvider,
                            $anchorScrollProvider) {

                            $anchorScrollProvider.disableAutoScrolling();

                            // Setup the routes
                            $routeProvider.when("/main", {
                                controller: "mainController",
                                controllerAs: "main",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/main.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations", {
                                controller: "moveSelectionController",
                                controllerAs: "move_options_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/move_options.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/docroot", {
                                controller: "docrootController",
                                controllerAs: "docroot",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/docroot.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/email", {
                                controller: "emailSelectionController",
                                controllerAs: "email_selection_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/email_options.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/databases", {
                                controller: "databaseSelectionController",
                                controllerAs: "db_selection_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/db_options.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/dns", {
                                controller: "dnsSelectionController",
                                controllerAs: "dns",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/dns.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/subaccounts", {
                                controller: "subaccountSelectionController",
                                controllerAs: "sub_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/subaccounts.ptt")
                            });

                            $routeProvider.when("/history", {
                                controller: "historyController",
                                controllerAs: "history",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/history.ptt")
                            });

                            $routeProvider.when("/history/:jobid/detail", {
                                controller: "conversionDetailController",
                                controllerAs: "detail",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/conversion_detail.ptt"),
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/main"
                            });
                        }
                    ]);

                    app.run(["$rootScope", "$anchorScroll", "$timeout", "$location", "growl", "growlMessages",
                        function($rootScope, $anchorScroll, $timeout, $location, growl, growlMessages) {

                            // account for the extra margin from the pageContainer div
                            $anchorScroll.yOffset = 41;
                        }
                    ]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

