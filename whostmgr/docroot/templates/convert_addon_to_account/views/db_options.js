/*
# views/db_options.js                             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, CPANEL: false */

define(
    [
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
