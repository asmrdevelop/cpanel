/* global DOM, angular */
(function list_db_objects(window) {
    "use strict";

    var pageData = window.PAGE;
    var CPANEL = window.CPANEL;
    var LOCALE = window.LOCALE;

    var db_object_type = pageData.db_object_type;

    var MIN_PW_STRENGTH = pageData.min_pw_strength;

    var toggleSort = function(tableOptionsObj, fieldName) {
        tableOptionsObj.reverse = (tableOptionsObj.order === fieldName) && !tableOptionsObj.reverse;
        tableOptionsObj.order = fieldName;
    };

    var selectedHeaderClass = function(column) {
        var className = "icon-arrow-" + (this.meta.reverse ? "down" : "up");
        return column === this.meta.order && className;
    };

    var selectedColClass = function(column) {
        return column === this.meta.order && "active";
    };

    var toggleEdit = function(ctx, dbobj) {
        dbobj.inEdit = !dbobj.inEdit;
    };

    var rename_type_engine_func = {
        mysql: {
            user: "rename_mysql_user",
            database: "rename_mysql_database"
        },
        postgresql: {
            user: "rename_postgresql_user",
            database: "rename_postgresql_database"
        }
    };

    var password_engine_func = {
        mysql: "set_mysql_password",
        postgresql: "set_postgresql_password"
    };

    var getRenameWarning = function(dbobj) {
        /* jshint scripturl:true*/
        return LOCALE.maketext("It is a potentially dangerous operation to rename a MySQL database. You may want to [output,url,_1,log into this user’s cPanel interface and back up this database] before renaming it.", "javascript:document.getElementById('xfer_cpanel_" + dbobj.cpuser + "').submit()");
    };

    var submitDbObjectEdit = function(dbobj) {
        var batch_members = [];

        validatePassword.call(this, dbobj);
        validateName.call(this, dbobj);

        if (dbobj.error && Object.keys(dbobj.error).length) {
            return;
        }

        var actions = {
            set_password: !!dbobj.password,
            rename: dbobj.newName && (dbobj.name !== dbobj.newName)
        };

        // The PostgreSQL rename API call sets the password, so don't do an
        // "extra" password set if the rename will set the password anyway.
        if (actions.set_password) {
            if (!actions.rename || (dbobj.engine !== "postgresql")) {
                batch_members.push({
                    func: password_engine_func[dbobj.engine],
                    data: {
                        cpuser: dbobj.cpuser,
                        user: dbobj.name,
                        password: dbobj.password
                    }
                });
            }
        }

        if (actions.rename) {
            var rename_call = {
                func: rename_type_engine_func[dbobj.engine][db_object_type],
                data: {
                    cpuser: dbobj.cpuser,
                    oldname: dbobj.name,
                    newname: dbobj.newName,
                }
            };

            // In PostgreSQL we do the password change as part of the rename.
            if (actions.set_password && (dbobj.engine === "postgresql")) {
                rename_call.data.password = dbobj.password;
            }

            batch_members.push(rename_call);
        }

        var ng_scope = this.$parent;

        if (batch_members.length) {
            var success_message;
            if (db_object_type === "user") {
                if (actions.rename) {
                    if (actions.set_password) {
                        if (dbobj.engine === "mysql") {
                            success_message = LOCALE.maketext("You have successfully renamed the [asis,MySQL] user “[_1]” to “[_2]” and set its password.", dbobj.name.html_encode(), dbobj.newName.html_encode());
                        } else if (dbobj.engine === "postgresql") {
                            success_message = LOCALE.maketext("You have successfully renamed the [asis,PostgreSQL] user “[_1]” to “[_2]” and set its password.", dbobj.name.html_encode(), dbobj.newName.html_encode());
                        }
                    } else {
                        if (dbobj.engine === "mysql") {
                            success_message = LOCALE.maketext("You have successfully renamed the [asis,MySQL] user “[_1]” to “[_2]”.", dbobj.name.html_encode(), dbobj.newName.html_encode());
                        } else if (dbobj.engine === "postgresql") {
                            success_message = LOCALE.maketext("You have successfully renamed the [asis,PostgreSQL] user “[_1]” to “[_2]”.", dbobj.name.html_encode(), dbobj.newName.html_encode());
                        }
                    }
                } else if (actions.set_password) {
                    if (dbobj.engine === "mysql") {
                        success_message = LOCALE.maketext("You have successfully set the password for the [asis,MySQL] user “[_1]”.", dbobj.name.html_encode());
                    } else if (dbobj.engine === "postgresql") {
                        success_message = LOCALE.maketext("You have successfully set the password for the [asis,PostgreSQL] user “[_1]”.", dbobj.name.html_encode());
                    }
                }
            } else if (db_object_type === "database") {
                if (actions.rename) {
                    if (dbobj.engine === "mysql") {
                        success_message = LOCALE.maketext("You have successfully renamed the [asis,MySQL] database “[_1]” to “[_2]”.", dbobj.name.html_encode(), dbobj.newName.html_encode());
                    } else if (dbobj.engine === "postgresql") {
                        success_message = LOCALE.maketext("You have successfully renamed the [asis,PostgreSQL] database “[_1]” to “[_2]”.", dbobj.name.html_encode(), dbobj.newName.html_encode());
                    }
                }
            }

            // Just in case. This should never happen in production
            // but helped with debugging during development.
            if (!success_message) {
                success_message = "INTERNAL ERROR: Success, but unknown action or DB object type!";
            }

            var edit_area_el = CPANEL.Y.one("#edit_" + dbobj.engine + "_" + dbobj.name);

            var overlay = new CPANEL.ajax.Page_Progress_Overlay(null, {
                covers: edit_area_el,
            });
            overlay.show();

            var notice_container_id_prefix = "notice_area_for_" + dbobj.engine + "_";

            var api_page_notice;

            var api_callback_function = function() {
                dbobj.name = dbobj.newName;
                dbobj.password = "";

                ng_scope.$apply();

                if(CPANEL.dom.get_viewport_region().contains(DOM.getRegion(edit_area_el))){
                    api_page_notice = new CPANEL.widgets.Dynamic_Page_Notice(null, { // eslint-disable-line camelcase
                        container: notice_container_id_prefix + dbobj.name, // eslint-disable-line camelcase
                        level: "success",
                        content: success_message
                    });
                } else {
                    // If the browser, for whatever reason, no longer has
                    // the edit area in the viewport, then we should show
                    // a "Growl" notice as some indicator of success.
                    api_page_notice = new CPANEL.ajax.Dynamic_Notice(null, { // eslint-disable-line camelcase
                        level: "success",
                        fade_delay: CPANEL.widgets.Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME,
                        content: success_message
                    });
                }
            };

            var api_callback_options = {
                hide_on_return: overlay,
                pagenotice_container: notice_container_id_prefix + dbobj.name
            };

            var api_call = {
                callback: CPANEL.ajax.build_page_callback(
                    api_callback_function,
                    api_callback_options
                )
            };

            if (batch_members.length > 1) {
                api_call.batch = batch_members;
            } else {
                angular.extend(api_call, batch_members[0]);
            }

            CPANEL.api(api_call);
        }
    };

    var verify_func_name = {
        mysql: {
            database: "verify_mysql_database_name",
            user: "verify_mysql_username"
        },
        postgresql: {
            database: "verify_postgresql_database_name",
            user: "verify_postgresql_username"
        }
    };

    var validateName = function(dbobj) {
        var name = dbobj.newName;
        try {
            CPANEL.sql[verify_func_name[dbobj.engine][db_object_type]](name);

            if (dbobj.error) {
                delete dbobj.error.name;
            }
        } catch (e) {
            if (!dbobj.error) {
                dbobj.error = {};
            }

            dbobj.error.name = e.toString();
        }
    };

    var password_strength_cache = {};

    var password_strength_api_call;

    var validatePassword = function(dbobj) {
        dbobj.passwordStrength = null;
        dbobj.passwordStrengthStr = "";

        var parentScope = this.$parent;

        if (!dbobj.error) {
            dbobj.error = {};
        }

        var password = dbobj.password;
        if (password) {
            var do_validation_update = function() {
                if (dbobj.passwordStrength < MIN_PW_STRENGTH[dbobj.engine]) {
                    dbobj.error.password = LOCALE.maketext("This password is too weak. Add more combinations of lowercase and uppercase letters, numerals, and symbols. (The minimum strength is [numf,_1]).", MIN_PW_STRENGTH[dbobj.engine]);
                } else if (dbobj.error) {
                    delete dbobj.error.password;
                }
            };

            if (password_strength_cache[password]) {
                dbobj.passwordStrength = password_strength_cache[password];
                dbobj.passwordStrengthStr = LOCALE.numf(dbobj.passwordStrength);
                do_validation_update();
            } else {
                if (password_strength_api_call) {
                    YAHOO.util.Connect.abort(password_strength_api_call);
                }

                password_strength_api_call = CPANEL.api({
                    func: "get_password_strength",
                    data: {
                        password: password
                    },
                    callback: CPANEL.ajax.build_page_callback(
                        function(o) {
                            dbobj.passwordStrength = o.cpanel_data.strength;
                            dbobj.passwordStrengthStr = LOCALE.numf(dbobj.passwordStrength);
                            do_validation_update();

                            password_strength_cache[password] = dbobj.passwordStrength;
                            parentScope.$apply();
                        }
                    )
                });

                dbobj.error.password = null;
            }
        } else if ((dbobj.newName !== dbobj.name) && (dbobj.engine === "postgresql") && (db_object_type === "user")) {
            dbobj.error.password = LOCALE.maketext("Provide a password to set for this user.");
        } else {
            delete dbobj.error.password;
        }
    };

    var renameSize = function(dbobj) {
        var name = dbobj.name;
        var maxlength = CPANEL.sql.get_name_length_limit(dbobj.engine, db_object_type);
        return Math.min(maxlength, name.length + 10);
    };

    var all_possible_page_sizes = [
        10,
        50,
        200,
        500,
        1000
    ];

    var updatePageSizes = function() {
        var $scope = this;

        var filtered_objects = ($scope.meta && $scope.meta.filteredResults || pageData.db_objects);

        $scope.pageSizes = all_possible_page_sizes
            .filter(function(n) {
                return (n < filtered_objects.length);
            })
            .map(function(n) {
                return {
                    label: LOCALE.maketext("Show [quant,_1,record,records]", n),
                    value: n
                };
            });

        $scope.pageSizes.push({
            label: LOCALE.maketext("Show all [quant,_1,record,records]", filtered_objects.length),
            value: 0
        });
    };

    angular.module("template/pagination/pagination.html", ["ui.bootstrap"])
        .run(["$templateCache",
            function($templateCache) {
                $templateCache.put(
                    "template/pagination/pagination.html",
                    document.getElementById("ng_pagination_html").text
                );
            }
        ]);

    var app = angular.module("getAcctList", ["ui.bootstrap"]);

    app.filter("cpLimitTo", function() {
        return function(input, limit) {
            return limit ? input.slice(0, limit) : input;
        };
    });

    app.filter("trustAsHtml", ["$sce",
        function($sce) {
            return function(val) {
                return $sce.trustAsHtml(val);
            };
        }
    ]);

    app.controller("initData", ["$scope",
        function($scope) {
            window.scope = $scope;
            $scope.all_db_objects = pageData.db_objects;
            $scope.empty_message = pageData.empty_message;

            $scope.engineToDisplay = {
                mysql: "MySQL",
                postgresql: "PostgreSQL"
            };

            $scope.show_search = pageData.db_objects.length > 1;
            $scope.expand_all_rows = !$scope.show_search;

            $scope.renameSize = renameSize;

            $scope.CPANEL = CPANEL;
            $scope.LOCALE = LOCALE;

            $scope.validateName = validateName;
            $scope.validatePassword = validatePassword;

            $scope.db_object_type = db_object_type;
            $scope.getRenameWarning = getRenameWarning;
            $scope.toggleSort = toggleSort;
            $scope.toggleEdit = toggleEdit;
            $scope.selectedHeaderClass = selectedHeaderClass;
            $scope.selectedColClass = selectedColClass;
            $scope.submitDbObjectEdit = submitDbObjectEdit;

            $scope.pageSizes = [];
            $scope.updatePageSizes = updatePageSizes;


            $scope.meta = {
                currentPage: 1,
                filteredResults: $scope.all_db_objects
            };

            $scope.filterMsg = function() {
                if ($scope.meta.filter) {
                    return LOCALE.maketext("Your search matched [numf,_1] of [quant,_2,record,records].", $scope.meta.filteredResults.length, $scope.all_db_objects.length);
                } else {
                    return LOCALE.maketext("There [numerate,_1,is,are] [quant,_1,record,records].", $scope.all_db_objects.length);
                }
            };

            $scope.updatePageSizes();

            $scope.meta.pageSize = $scope.pageSizes[0].value;

            $scope.$watch("meta.filteredResults.length", function(newValue, oldValue) {
                if (newValue !== oldValue) {
                    $scope.updatePageSizes();
                }
            });

        }
    ]);

    app.filter("startFrom", function() {
        return function(input, start) {
            start = +start; // parse to int
            return input.slice(start);
        };
    });

    // https://gist.github.com/tommaitland/7579618
    app.directive("ngDebounce", ["$timeout",
        function($timeout) {
            return {
                restrict: "A",
                require: "ngModel",
                priority: 99,
                link: function(scope, elm, attr, ngModelCtrl) {
                    if (attr.type === "radio" || attr.type === "checkbox") {
                        return;
                    }

                    elm.unbind("input");

                    var debounce;

                    elm.bind("input", function() {
                        $timeout.cancel(debounce);
                        debounce = $timeout(function() {
                            scope.$apply(function() {
                                ngModelCtrl.$setViewValue(elm.val());
                            });
                        }, 250);
                    });

                    elm.bind("blur", function() {

                        // http://stackoverflow.com/questions/12729122/prevent-error-digest-already-in-progress-when-calling-scope-apply
                        $timeout(function() {
                            scope.$apply(function() {
                                ngModelCtrl.$setViewValue(elm.val());
                            });
                        });
                    });
                }
            };
        }
    ]);
})(window);
