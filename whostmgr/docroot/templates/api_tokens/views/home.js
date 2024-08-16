/*
# cpanel - whostmgr/docroot/templates/api_tokens/views/home.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/


define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/util/table",
        "uiBootstrap",
        "cjt/decorators/growlDecorator",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/alertList",
        "cjt/directives/toggleSortDirective",
        "cjt/services/viewNavigationApi",
        "cjt/directives/autoFocus",
    ],
    function(angular, LOCALE, Table) {
        "use strict";
        var app = angular.module("whm.apiTokens");

        var controller = app.controller(
            "homeController",
            ["$q", "growl", "Tokens", "$uibModal", "viewNavigationApi", "PAGE",
                function($q, growl, Tokens, $uibModal, viewNavigationApi, PAGE) {
                    var home = this;

                    home.loading = false;
                    home.showFormToggleBtn = true;
                    home.tokenAdded = false;
                    home.loadingError = false;
                    home.loadingErrorMessage = "";
                    home.allChecked = false;
                    home.checkedCount = 0;
                    home.paginationMessage = "";
                    home.showChildAccountsExistWarning = PAGE.childAccountsExist;
                    home.childAccountsExistWarning = "";
                    home.childAccountsExistWarning += LOCALE.maketext("There are accounts on this server controlled by a parent node.");
                    home.childAccountsExistWarning += " ";
                    home.childAccountsExistWarning += LOCALE.maketext("Do not delete [asis,API] tokens a parent node uses to communicate with this server.");

                    function searchByName(item, searchText) {
                        return item.name.toLowerCase().indexOf(searchText.toLowerCase()) !== -1;
                    }

                    var table = new Table();
                    table.setSearchFunction(searchByName);
                    table.setSort("create_time,name", "desc");
                    home.meta = table.getMetadata();
                    home.filteredList = table.getList();
                    home.allTokens = [];
                    home.render = function() {
                        home.resetCheckAll();
                        home.filteredList = table.update();
                        home.paginationMessage = table.paginationMessage();
                    };
                    home.sortList = function() {
                        home.render();
                    };
                    home.selectPage = function() {
                        home.render();
                    };
                    home.selectPageSize = function() {
                        home.render();
                    };
                    home.searchList = function() {
                        home.render();
                    };

                    home.resetCheckAll = function() {
                        home.allChecked = false;
                        home.toggleCheckAll();
                        home.checkedCount = 0;
                    };

                    home.getIndeterminateState = function() {
                        return home.checkedCount > 0 && !home.allChecked;
                    };

                    home.toggleCheckAll = function() {
                        if (home.filteredList.length === 0) {
                            return;
                        }
                        var i = 0, listLength = home.filteredList.length;
                        for (i; i < listLength; i++) {
                            home.filteredList[i].checked = home.allChecked;
                        }
                        if (home.allChecked) {
                            home.checkedCount = listLength;
                        } else {
                            home.checkedCount = 0;
                        }
                    };

                    home.syncCheckAll = function(listItem) {
                        if (listItem.checked) {
                            home.checkedCount++;
                        } else {
                            home.checkedCount--;
                        }
                        home.allChecked = home.checkedCount === home.filteredList.length;
                    };

                    home.checkAll = function() {
                        home.allChecked = true;
                        home.toggleCheckAll();
                    };

                    home.editToken = function(token) {
                        if (token === void 0) {
                            viewNavigationApi.loadView("/edit");
                        } else {
                            viewNavigationApi.loadView("/edit/" + token.name);
                        }
                    };

                    home.getSelectedTokens = function() {
                        var selectedTokens = [];
                        for (var i = 0; i < home.filteredList.length; i++) {
                            if (home.filteredList[i].checked) {
                                selectedTokens.push(home.filteredList[i]);
                            }
                        }

                        return selectedTokens;
                    };

                    home.getHumanReadableTime = function(epochTime) {
                        return LOCALE.local_datetime(epochTime, "datetime_format_medium");
                    };

                    function RevokeTokenModalController($uibModalInstance, token) {
                        var ctrl = this;
                        var tokenCount = 0;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };

                        ctrl.buildTokenNameList = function() {
                            tokenCount = token.length;
                            var i = 0, tokensToDelete = [];

                            for (i = 0; i < tokenCount; i++) {
                                tokensToDelete.push(token[i].name);
                            }

                            return tokensToDelete;
                        };

                        var revokeParam;

                        if (Array.isArray(token) && token.length === home.allTokens.length) {
                            ctrl.prompt = LOCALE.maketext("Are you certain that you want to revoke all of your [asis,API] tokens?" );
                            revokeParam = ctrl.buildTokenNameList();
                        } else if (Array.isArray(token)) {
                            ctrl.prompt = LOCALE.maketext("Are you certain that you want to revoke [numf,_1] [asis,API] [numerate,_1,token,tokens]?", token.length);
                            revokeParam = ctrl.buildTokenNameList();
                        } else {
                            ctrl.prompt = LOCALE.maketext("Are you certain that you want to revoke the [asis,API] token, “[_1]”?", token.name);
                            revokeParam = token.name;
                        }

                        ctrl.confirm = function() {
                            return Tokens.revokeToken(revokeParam)
                                .then(function() {
                                    if (Array.isArray(token)) {
                                        if (token.length === home.allTokens.length) {
                                            growl.success(LOCALE.maketext("You successfully revoked all of your [asis,API] tokens."));
                                            table.clear();
                                            home.allTokens = [];
                                        } else {
                                            growl.success(LOCALE.maketext("You successfully revoked [numf,_1] [asis,API] [numerate,_1,token,tokens].", token.length));
                                            for (var i = 0; i < tokenCount; i++) {
                                                table.remove(token[i]);
                                            }
                                        }
                                    } else {
                                        growl.success(LOCALE.maketext("You successfully revoked the [asis,API] token “[_1]”.", token.name));
                                        table.remove(token);
                                    }

                                    home.render();
                                })
                                .catch(function(error) {
                                    growl.error(error);
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }

                    RevokeTokenModalController.$inject = ["$uibModalInstance", "token"];

                    home.confirmRevokeToken = function(token) {
                        $uibModal.open({
                            templateUrl: "confirm_token_revocation.html",
                            controller: RevokeTokenModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                token: function() {
                                    return token;
                                },
                            },
                        });
                    };

                    home.refreshList = function() {
                        home.filteredList = [];
                        home.allTokens = [];
                        return load();
                    };

                    function load() {
                        home.loading = true;

                        var _currentDateTime = new Date();
                        _currentDateTime = _currentDateTime.getTime() / 1000;

                        var _twentyFourHours = 24 * 60 * 60;

                        // In addition to getting the list of api tokens, we want to fetch the
                        // privileges for the user now to cache them for when the user will
                        // need to create a token. This helps avoid showing a spinner on the
                        // create view.
                        return $q.all([
                            Tokens.getTokens(true),
                            Tokens.getPrivileges(true)])
                            .then(function(data) {
                                var tableData = [];
                                var tokenData = data[0];
                                if (tokenData !== null && typeof tokenData !== "undefined") {
                                    for (var tokenName in tokenData) {
                                        if (tokenData.hasOwnProperty(tokenName)) {
                                            tokenData[tokenName].checked = false;
                                            tokenData[tokenName].create_time_friendly = LOCALE.local_datetime(tokenData[tokenName].create_time, "datetime_format_medium");
                                            tokenData[tokenName].expiresAtFriendly = "";
                                            if (tokenData[tokenName].expires_at) {

                                                var expiresAt = parseInt(tokenData[tokenName].expires_at, 10);

                                                if (expiresAt <= _currentDateTime) {
                                                    tokenData[tokenName].expired = true;
                                                } else if (expiresAt - _currentDateTime < _twentyFourHours) {
                                                    tokenData[tokenName].expiresSoon = true;
                                                }

                                                tokenData[tokenName].expiresAtFriendly = LOCALE.local_datetime(tokenData[tokenName].expires_at, "datetime_format_medium");
                                            }
                                            tableData.push(tokenData[tokenName]);
                                        }
                                    }
                                    table.load(tableData);
                                    home.allTokens = tableData;
                                    home.render();
                                }
                            })
                            .catch(function(error) {
                                home.loadingError = true;
                                home.loadingErrorMessage = error;
                            })
                            .finally(function() {
                                home.loading = false;
                            });
                    }

                    function init() {
                        load();
                    }

                    init();
                },
            ]);

        return controller;
    }
);
