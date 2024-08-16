/*
# templates/transfer_tool/controllers/AccountTableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

/* jshint -W003 */
/* jshint -W098*/

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/services/workerNodes",
        "app/filters/startFromFilter",
        "app/filters/cpLimitToFilter",
        "app/filters/accountFilter",
        "app/filters/advanceAccountFilter",
        "cjt/services/whm/nvDataService",
    ],
    function(angular, LOCALE, PARSE, WorkerNodesService) {

        "use strict";

        var DEFAULT_CUSTOMIZED_LABEL = LOCALE.maketext("Default");
        var CUSTOM_CUSTOMIZED_LABEL = LOCALE.maketext("Custom");

        var SKIP_FLAG_DEFAULTS = {
            "copy_homedir": 1,
            "copy_databases": 1,
            "copy_bwdata": 1,
            "copy_reseller_privs": 0
        };

        var CONTROLLER_INJECTABLES = ["$scope", "$rootScope", WorkerNodesService.serviceName, "$filter", "$uibModal", "PAGE", "nvDataService", "OVERWRITE_OPTIONS", "OVERWRITE_STATES", "OVERWRITE_DESCRIPTION_TEMPLATE"];

        /**
         * @class Controller class for the account table.  Used in the angular app with 'controller as'.  This contains most logic pertaining to accounts.
         * @param {object} $scope
         * @param {object} $filter
         */
        var AccountTableController = function($scope, $rootScope, $workerNodesService, $filter, $uibModal, PAGE, nvDataService, OVERWRITE_OPTIONS, OVERWRITE_STATES, OVERWRITE_DESCRIPTION_TEMPLATE) {
            var _this = this;

            _this.PAGE = PAGE;
            _this.disableLiveTransfers = _this.PAGE.disable_live_transfers;
            _this.isRestrictedRestore = _this.PAGE.restricted_restore;
            _this.isRTL = PAGE.locale_is_rtl.toString() === "1";

            _this.overwriteOptions = OVERWRITE_OPTIONS;

            _this.reservedUsernamePatterns = _this.PAGE.local.reserved_username_patterns;
            _this.localUserHash = Object.create(null);
            _this.reservedUsernames = {};
            _this.localPartialUsernames = {};

            _this.defaultWorkerOptions = $workerNodesService.getDefaultWorkerOptions();
            _this.workerOptionTypes = $workerNodesService.getWorkerOptionTypes();

            _this.control_overwrite = _this.overwriteOptions[0];
            _this.overwriteStates = OVERWRITE_STATES;

            _this.accountFilterText = "";
            _this.acctTable = {
                currentPage: 1,
                pageSize: 10,
                reverse: false,
                order: "remote_user",
                advSearchOptions: {
                    domain: "",
                    user: "",
                    owner: [],
                    dedicated_ip: -1
                },
                activeAdvFilter: null
            };

            _this.getDedicatedIPDomains = function() {
                return _this.PAGE.domainsWithDedicatedIp;
            };

            // This will require more logic as the banner messages that can reset dedicated
            // IP addresses so for now we are returning the status
            // quo of always displaying the column.
            _this.showDedicatedIPColumn = true;

            var supportsExpressTransfers = PAGE.remote ? PARSE.parsePerlBoolean(PAGE.remote.supports_express_transfers) : false;
            var supportsLiveTransfers = PAGE.remote ? PARSE.parsePerlBoolean(PAGE.remote.supports_live_transfers) : false;

            // If we support live transfers, it defaults to on
            // Unless it has been disabled
            var PROXY_FLAG_DEFAULT = supportsLiveTransfers && !_this.disableLiveTransfers;
            $scope.supportsLiveTransfers = supportsLiveTransfers;

            $scope.liveTransfersNoticeIsDismissed = PAGE.liveTransfersNoticeIsDismissed;
            $scope.liveTransfersPre90NoticeIsDismissed = PAGE.liveTransfersPre90NoticeIsDismissed;
            $scope.isAcctTabActive = true;

            // Overload the live transfer support. This gets set when the hostname is invalid.
            // We also need to overload and hide the notifications for live transfers
            if (_this.disableLiveTransfers) {
                $scope.liveTransfersNoticeIsDismissed = true;
            }

            $scope.dismissLiveTransfersNotice = function dismissLiveTransfersNotice() {
                $scope.liveTransfersNoticeIsDismissed = true;
                nvDataService.set("live_transfers_notice_is_dismissed", 1);
            };

            $scope.dismissLiveTransfersPre90Notice = function dismissLiveTransfersPre90Notice() {
                $scope.liveTransfersPre90NoticeIsDismissed = true;
                $scope.liveTransfersNoticeIsDismissed = true;

                nvDataService.set("live_transfers_pre_90_notice_is_dismissed", 1);
            };

            $rootScope.showTable = function showTable() {
                return !$scope.isAcctTabActive || (!$scope.supportsLiveTransfers || ($scope.supportsLiveTransfers && $scope.liveTransfersNoticeIsDismissed));
            };

            $rootScope.setAcctTabActive = function(isAcctTabActive) {
                $scope.isAcctTabActive = isAcctTabActive;
            };

            _this.createUser = function(obj, index) {
                obj.initialindex = index;
                obj.copy_homedir = SKIP_FLAG_DEFAULTS["copy_homedir"];
                obj.copy_databases = SKIP_FLAG_DEFAULTS["copy_databases"];
                obj.copy_bwdata = SKIP_FLAG_DEFAULTS["copy_bwdata"];
                obj.copy_reseller_privs  = SKIP_FLAG_DEFAULTS["copy_reseller_privs"];
                obj.copy_proxy_option = PROXY_FLAG_DEFAULT;
                obj.proxyOption = {
                    id: "proxy_option",
                    modelKey: "copy_proxy_option",
                    value: PROXY_FLAG_DEFAULT,
                    default: PROXY_FLAG_DEFAULT,
                    supports_live_transfers: PROXY_FLAG_DEFAULT,
                    supports_express_transfers: supportsExpressTransfers,
                };
                obj.selected = 0;
                obj.overwrite_type = _this.overwriteOptions[0];
                obj.overwrite_account = 0;
                obj.overwrite_with_delete = 0;
                obj.userCheckStates = {
                    duplicate: false,
                    reserved: false,
                    existing: false
                };
                obj.dedicated_ip = (obj.dedicated_ip || _this.getDedicatedIPDomains()[obj.domain]) ? 1 : 0;
                obj.existing_dedicated_ip = obj.dedicated_ip;
                obj.oldlocaluser = obj.user;
                obj.localuser = obj.user;
                obj.invalidDomain = _this.PAGE.local.domains[obj.domain] && _this.PAGE.local.domains[obj.domain] !== obj.user ? 1 : 0;
                obj.is_reseller = _this.PAGE.remote.resellers && _this.PAGE.remote.resellers[obj.remote_user] ? 1 : 0;
                obj.invalidUser = _this.PAGE.local.users[obj.remote_user] ? 1 : 0;
                obj.isCustomized = false;
                obj.workerNodes = obj.worker_nodes || {};

                // This is done in the service because it's done in multiple controllers
                $workerNodesService.resetAccountToDefaults(obj);
            };

            _this.expandedAccount = false;

            _this.PAGE.items.accounts.forEach(_this.createUser);

            var accountFilter = $filter("accountFilter"),
                advanceAccountFilter = $filter("advanceAccountFilter"),
                startFrom = $filter("startFrom"),
                orderBy = $filter("orderBy"),
                limitTo = $filter("cpLimitTo");


            // To better understand what these assignments are look at updateFilteredAccounts and updateViewableAccounts
            _this.filteredAccounts = accountFilter(advanceAccountFilter(this.PAGE.items.accounts, _this.acctTable.activeAdvFilter), _this.accountFilterText);
            _this.viewableAccounts = limitTo(startFrom(orderBy(_this.filteredAccounts, _this.acctTable.order, _this.acctTable.reverse), (_this.acctTable.currentPage - 1) * _this.acctTable.pageSize),
                _this.acctTable.pageSize);

            /**
            * Reapplies filters for the filteredAccounts array
            * Array    ->    Filtered by advanced             -> filtered by basic
            * accounts | advanceAccountFilter:activeAdvFilter | accountFilter:accountFilterText
            */
            _this.updateFilteredAccounts = function() {
                _this.filteredAccounts = accountFilter(
                    advanceAccountFilter(this.PAGE.items.accounts, _this.acctTable.activeAdvFilter), _this.accountFilterText);
            };

            /**
            * Reapplies filteres for the viewableAccounts array.
            * FilteredArray    ->              Ordered by(reverse?)         ->          start based on page #                             ->    limit to page size
            * filteredAccounts | orderBy: acctTable.order:acctTable.reverse | startFrom:(acctTable.currentPage - 1 ) * acctTable.pageSize | limitTo: acctTable.pageSize
            */
            _this.updateViewableAccounts = function() {
                var pageSize = _this.acctTable.pageSize;
                var accounts = orderBy(_this.filteredAccounts, _this.acctTable.order, _this.acctTable.reverse);
                accounts = limitTo(startFrom(accounts, (_this.acctTable.currentPage - 1) * pageSize), pageSize);
                _this.viewableAccounts = accounts;
            };

            _this.getUsernamePattern = function(key) {
                if (key === "TRIM_PATTERN") {
                    return new RegExp(_this.PAGE.UN_TRIM_REG_EXP);
                } else if (key === "TRANSFER_USER_RESTRICT") {
                    return new RegExp(_this.PAGE.USERNAME_TRANSFER_REGEXP);
                } else if (key === "NONTRANSFER_USER_RESTRICT") {
                    return new RegExp(_this.PAGE.USERNAME_REGEXP);
                } else {
                    return null;
                }
            };

            $scope.$on("recheckUsersCalled", function(eo, args) {
                angular.forEach(args.dataset, function(acct) {

                    // Always skip forcing selection, since "Select None" will cause this to just get re-selected
                    _this.updateOverwriteFlags(acct, false, true);
                    _this.updateUserCheckStates(acct);
                    _this.checkAccountForDuplicateLocals(acct);
                    _this.updateAccountsControlRow();
                });
            });

            $scope.$on("selectedAccountsEmptied", function() {
                _this.acct_checkbox_control = false;
                _this.updateAccountsControlRow();
            });

            $scope.$watch(function() {
                return _this.acctTable;
            }, function() {
                _this.updateViewableAccounts();
            }, true);

            $scope.$watch(function() {
                return _this.viewableAccounts;
            }, function() {
                _this.updateAccountsControlRow();
            }, true);

            for (var rUi = 0; rUi < _this.PAGE.local.reserved_usernames.length; rUi++) {
                var reservedUsername = _this.PAGE.local.reserved_usernames[rUi].toLowerCase();
                _this.reservedUsernames[reservedUsername] = 1;
            }

            /* used to check the eight v 16 restrictions of (no same first USERNAME_UNIQUE_LENGTH characters) */
            /* pre processed for big lists */

            angular.forEach(_this.PAGE.local.users, function(value, lUsername) {
                var plUsername = _this.makeUsernamePartial(lUsername, true);
                this[plUsername] = lUsername;
            }, _this.localPartialUsernames);

            angular.forEach(_this.PAGE.items.accounts, function(acct, key) {

                /* store local user hash */
                _this.storeLocalUserHash(acct.initialindex, acct.oldlocaluser, acct.localuser);
            });

            // Set the columnWidth

            _this.numberOfColumns = 9;
            ["bytesused", "owner", "dedicated_ip"].forEach(function(key) {
                if (!_this.showColumn(key)) {
                    _this.numberOfColumns--;
                }
            });

            _this.skipOptions = [
                { id: "copy_homedir_for", label: LOCALE.maketext("Home Directory"), modelKey: "copy_homedir", default: SKIP_FLAG_DEFAULTS["copy_homedir"] },

                // Disable reseller privileges skipOption for restricted restores
                { id: "reseller_privs_for", label: LOCALE.maketext("Reseller Privileges"), modelKey: "copy_reseller_privs", default: SKIP_FLAG_DEFAULTS["copy_reseller_privs"], disabled: _this.isRestrictedRestore },
                { id: "copy_acctdb_for", label: LOCALE.maketext("Databases"), modelKey: "copy_databases", default: SKIP_FLAG_DEFAULTS["copy_databases"] },
                { id: "copy_bwdata_for", label: LOCALE.maketext("Bandwidth Data"), modelKey: "copy_bwdata", default: SKIP_FLAG_DEFAULTS["copy_bwdata"] },
            ];

            _this.openModal = $uibModal.open.bind($uibModal);
            _this.overwriteDescriptionTemplate = OVERWRITE_DESCRIPTION_TEMPLATE;

            this._workerOptionAltered = $workerNodesService.checkWorkerOptionsAltered.bind($workerNodesService);

            return _this;
        };

        angular.extend(AccountTableController.prototype, {

            /**
            * Stores hashed usernames for duplication checks on large amounts of usernames
            */
            storeLocalUserHash: function storeLocalUserHash(index, oldValue, newValue) {

                var _this = this;
                var newValuePartial = this.makeUsernamePartial(newValue, true);
                var oldValuePartial = this.makeUsernamePartial(oldValue, true);

                _this.localUserHash[oldValuePartial] = _this.localUserHash[oldValuePartial] || [];
                angular.forEach(_this.localUserHash[oldValuePartial], function(value, key) {
                    if (value === index) {
                        _this.localUserHash[oldValuePartial].splice(key, 1);
                    }
                });

                _this.localUserHash[newValuePartial] = _this.localUserHash[newValuePartial] || [];
                _this.localUserHash[newValuePartial].push(index);
            },

            /**
            * Calls functions that update filtered and viewable accounts
            */
            updateAccounts: function updateAccounts() {
                this.updateFilteredAccounts();
                this.updateViewableAccounts();
            },

            /**
            * Returns class corresponding to glyph for account.  Account must be selected and not have a domain conflict.
            * @param  {object} acct
            * @return {?string}
            */
            getGlyphClass: function getGlyphClass(acct) {
                if (!acct.selected || acct.domainConflict) {
                    return;
                }
                if (acct.invalidUser) {
                    return "glyphicon-exclamation-sign";
                } else {
                    return "glyphicon-ok";
                }
            },

            /**
            * Returns class for button that corresponds to what choice for dedicated ip was selected.  Used in advance search form to indicate selection similar to radio button.
            * @param  {int} thisVal
            * @return {string|Boolean}
            */
            dedicatedIpClass: function dedicatedIpClass(thisVal) {
                return thisVal === this.acctTable.advSearchOptions.dedicated_ip ? "btn-primary" : "btn-default";
            },

            /**
             * Check the state of the various control columns
             *
             * @param {object[]} accounts list of accounts to build the value based on
             * @param {string} param parameter on account to check
             * @returns {*} current value of control column. Various values possible.
             */
            _getColumnControlState: function _getColumnControlState(accounts, param) {

                // If there are no accounts, return false
                if (!accounts.length) {
                    return false;
                }

                // If any are not checked, return false
                for (var i = 0; i < accounts.length; i++) {
                    var account = accounts[i];
                    if (!account[param]) {
                        return false;
                    }
                }

                // If all are checked, return true
                return true;
            },

            /**
             * Check the state of the overwrite control column
             *
             * @param {object[]} accounts list of accounts to build the value based on
             * @param {string} param parameter on account to check
             * @returns {object|null} value of the parameter for accounts if the same. Undefined otherwise.
             */
            _getOverwriteColumnControlState: function _getOverwriteColumnControlState(accounts, param) {

                // Update only based on selected accounts in list

                // If there are no accounts, return false
                if (!accounts.length) {
                    return this.overwriteOptions[0];
                }

                var currentValue;
                for (var i = 0; i < accounts.length; i++) {
                    var account = accounts[i];
                    if (!this.canNeedOverwrite(account)) {

                        // Only ones that might need overwrite should be considered
                        continue;
                    }

                    // Store the first value as a baseline
                    if (!currentValue) {
                        currentValue = account[param];
                    }

                    // If any are different from one another, default to undef (to allow setting it)
                    if (account[param].value !== currentValue.value) {
                        return;
                    }
                }

                // If all are one of the two overwrite values [1,2], use that value
                // If no value was determined, then no overwrite-capable items were found, use the zero option
                return currentValue ? currentValue : this.overwriteOptions[0];
            },

            /**
            * Called to check and adjust control row check boxes based on viewable account params
            */
            updateAccountsControlRow: function updateAccountsControlRow() {

                var checks = [{
                    param: "selected",
                    controlModel: "acct_checkbox_control",
                    checkFunction: this._getColumnControlState.bind(this)
                }, {
                    param: "dedicated_ip",
                    controlModel: "control_dedicated_ip",
                    onlySelected: true,
                    checkFunction: this._getColumnControlState.bind(this)
                }, {
                    param: "overwrite_type",
                    controlModel: "control_overwrite",
                    onlySelected: true,
                    checkFunction: this._getOverwriteColumnControlState.bind(this)
                }];

                var selectedAccounts = this.viewableAccounts.filter(function(account) {
                    return !!account.selected;
                });

                angular.forEach(checks, function(check) {

                    var accounts = check.onlySelected ? selectedAccounts : this.viewableAccounts;
                    this[check.controlModel] = check.checkFunction(accounts, check.param);

                }, this);

            },

            /**
            * Sets the advance search($scope.acctTable.advSearchOptions) to either be a copy of the object passed in or if no object, to the default value.  We set it this way
            * because otherwise Angular will bind the object directily causing any updates to be instantaneous, breaking the experience.
            * @param {object} obj
            */
            setAdvanceSearch: function setAdvanceSearch(obj) {
                this.acctTable.activeAdvFilter = angular.copy(obj);
                this.updateAccounts();

                if (!obj) {
                    this.acctTable.advSearchOptions = {
                        domain: "",
                        user: "",
                        owner: [],
                        dedicated_ip: -1
                    };
                }
            },

            /**
            * Goes over array of accounts and sets the dedicated_ip flag if the destination domain already has a dedicated ip.
            * @param  {array} dataset
            */
            handleDedicatedIpForArray: function handleDedicatedIpForArray(dataset) {
                var _self = this;
                angular.forEach(dataset, function(acct) {
                    if (_self.getDedicatedIPDomains()[acct.domain]) {
                        acct.dedicated_ip = 1;
                    }
                });
            },

            /**
            * Returns true if the account has a destination domain with a dedicated ip already or if there are no available IP addresses.
            * @param  {object}  acct
            * @return {Boolean}
            */
            isDedicatedIpDisabled: function isDedicatedIpDisabled(acct) {
                return this.getDedicatedIPDomains()[acct.domain] ? true : !this.PAGE.local.available_ips.length;
            },

            /**
            * Returns true for account that can be overwritten
            * @param  {object} item
            * @return {Boolean}
            */
            overwriteFilter: function overwriteFilter(item) {
                return this.PAGE.local.users[item.user] || this.PAGE.local.users[item.localuser] || (this.PAGE.local.domains[item.domain] === item.localuser);
            },

            /**
            * Updates account username checks and stores then on acct.userCheckStates
            * then updates calls updateLocalUserStatus() to reset acct.invalidUser
            *
            * @method validateAccount
            * @param acct {Object} angular user account object
            */
            validateAccount: function validateAccount(acct) {

                // update account localuser hash for duplicate validation
                /* which large accounts this was the only feasible option. */
                /* deep watch expressions were far too cumbersome.  */
                this.storeLocalUserHash(acct.initialindex, acct.oldlocaluser, acct.localuser);

                /* must be called before oldusername is reset to reset duplication on old set */
                this.checkAccountForDuplicateLocals(acct);
                acct.oldlocaluser = acct.localuser;
                this.updateUserCheckStates(acct);

            },

            /**
            * Seperate function allows independent updates to userCheckStates
            * used in ToggleCheckAll
            *
            * @method updateuserCheckStatus
            * @param acct {Object} angular user account object
            */
            updateUserCheckStates: function updateUserCheckStates(acct) {

                /* response is now in the form of false, or failure object */
                acct.userCheckStates.reserved = this.isReservedUsername(acct);
                acct.userCheckStates.existing = this.isExistingLocalUser(acct);

                /* refers to the specific makeup of the new username (does it match the regexp) */
                acct.userCheckStates.invalid = !this.isLocalUsernameValid(acct);
                acct.overwrite_type = acct.selected ? acct.overwrite_type : this.overwriteOptions[0];
                this.updateLocalUserStatus(acct);
            },

            /**
            * updates 'invalidUser' based on state check flags
            *
            * @method updateLocalUserStatus
            * @param acct {Object} angular user account object
            */
            updateLocalUserStatus: function updateLocalUserStatus(acct) {
                if ((acct.userCheckStates.existing !== false && acct.overwrite_type.value === this.overwriteStates.NO_OVERWRITE ) ||
                    acct.userCheckStates.duplicate !== false ||
                    acct.userCheckStates.invalid !== false ||
                    acct.userCheckStates.reserved !== false) {
                    acct.invalidUser = true;
                } else {
                    acct.invalidUser = false;
                }
            },

            /**
            * Returns the class to be used for input field highlighting.
            * @param  {object} acct
            * @return {?string}
            */
            getInputClass: function getInputClass(acct) {
                if (!acct.selected || acct.domainConflict) {
                    return;
                }

                if (acct.invalidUser) {
                    return "has-error";
                } else {
                    return "has-success";
                }
            },

            /**
            * Returns username converted from account as as string
            *
            * @method getUserNameFromAcct
            * @param acct {Object} angular user account object
            * @return {String} value of username
            */
            getUserNameFromAcct: function getUserNameFromAcct(acct) {
                var username = acct.localuser || "";
                if (!username.length) {
                    username = acct.remote_user;
                }
                return username;
            },

            /**
            * Returns Array of accounts that the username matches (can be partial match).
            *
            * @method findAccountsByUsername
            * @param username {String} angular user account object
            * @param matchFirstNChars {int} number of matching characters defaults to all
            *        passing -1 will be treated as a 'match all characters'
            * @param startingIndex {int} which account to begin the interation from (faster)
            * @return {Array} of acct indexes that match
            */
            findAccountsByUsername: function findAccountsByUsername(username, matchFirstNChars, startingIndex) {

                /* if matchFirstNChars > 0 use matchFirstNChars | else use -1 (interpretted as all) */
                matchFirstNChars = Number(matchFirstNChars) || -1;
                startingIndex = Number(startingIndex) || 0;

                if (matchFirstNChars !== -1) {
                    username = username.substr(0, matchFirstNChars);
                }

                var matchedAccounts = [];

                var otherAccount;
                for (var i = startingIndex; i < this.PAGE.items.accounts.length; i++) {

                    otherAccount = this.PAGE.items.accounts[i];

                    if (otherAccount.localuser.toLowerCase().indexOf(username) === 0) {

                        if (username.length < matchFirstNChars && otherAccount.localuser.length > username.length) {

                            /* this means that the otherAccount has additional characters in the NChars range
                                    so it is no longer enough matching characters */
                            continue;
                        }

                        /* username was found in it */
                        if (matchFirstNChars === -1 && username.length !== otherAccount.localuser.length) {

                            /* matchFirstNChars is set to default (match all), but lengths of the usernames */
                            continue;
                        }

                        /* good length, good first n chars */
                        matchedAccounts.push(i);
                    }

                }

                return matchedAccounts;
            },

            /**
            * finds accounts by username, then returns selected accounts
            *
            * @method findSelectedAccountsByUsername
            * see: findAccountsByUsername for @params
            */
            findSelectedAccountsByUsername: function findSelectedAccountsByUsername( /* inherit from findAccountsByUsername */ ) {

                var usernames = this.findAccountsByUsername.apply(this, arguments);
                var selected = [];

                if (usernames === false) {
                    return selected;
                }

                var uIndex;
                for (var i = 0; i < usernames.length; i++) {
                    uIndex = usernames[i];
                    if (this.PAGE.items.accounts[uIndex].selected) {
                        selected.push(uIndex);
                    }
                }

                return selected;

            },

            /**
            * Checks one local account for duplicates and marks userCheckStates.duplicate accordingly
            *
            * @method checkAccountForDuplicateLocals
            */
            checkAccountForDuplicateLocals: function checkAccountForDuplicateLocals(acct) {

                /* clear status flag */
                acct.userCheckStates.duplicate = false;

                /* get oldlocaluser and reset old duplicates */

                var oldUsernamePartial = this.makeUsernamePartial(acct.oldlocaluser, true);

                /* recheck old username set to update their duplicate flag */
                if (this.localUserHash[oldUsernamePartial] && this.localUserHash[oldUsernamePartial].length === 1) {
                    var previousDuplicateUser = this.localUserHash[oldUsernamePartial][0];
                    this.PAGE.items.accounts[previousDuplicateUser].userCheckStates.duplicate = false;
                    this.updateLocalUserStatus(this.PAGE.items.accounts[previousDuplicateUser]);
                }

                /* no local username entered? Ignore it! */
                if (!acct.localuser) {
                    return;
                }

                var username = acct.localuser;
                var trimmedUsername = this.makeUsernamePartial(username, true);
                var accountIndexOrObject;
                var accountIndex;
                var selectedOthers = [];

                /* reset all, store still selected items for next loop */
                for (var i = 0; i < this.localUserHash[trimmedUsername].length; i++) {
                    accountIndex = this.localUserHash[trimmedUsername][i];

                    accountIndexOrObject = this.PAGE.items.accounts[accountIndex];

                    accountIndexOrObject.userCheckStates.duplicate = false;
                    this.updateLocalUserStatus(accountIndexOrObject);

                    /* items that aren't selected are ignored */
                    if (!accountIndexOrObject.selected) {
                        continue;
                    }

                    selectedOthers.push(accountIndexOrObject);
                }

                /* if multiple items remain selected in this hash, set them as duplicates */

                if (selectedOthers.length > 1) {


                    for (i = 0; i < selectedOthers.length; i++) {
                        accountIndexOrObject = selectedOthers[i];

                        accountIndexOrObject.userCheckStates.duplicate = true;
                        this.updateLocalUserStatus(accountIndexOrObject);
                    }

                }

            },

            /**
            * Checks all local accounts for duplicates and marks userCheckStates.duplicate accordingly
            *
            * @method checkForDuplicateLocals
            */
            checkForDuplicateLocals: function checkForDuplicateLocals() {

                /* check this username against other usernames that have been checked for transfer */
                var i, otherAccount;

                /* reset all initially to allow faster parsing later in function*/
                for (i = 0; i < this.PAGE.items.accounts.length; i++) {
                    otherAccount = this.PAGE.items.accounts[i];
                    otherAccount.userCheckStates.duplicate = false;
                    this.updateLocalUserStatus(otherAccount);
                }

                /* iterate through all, skip already set duplicates, */
                for (i = 0; i < this.PAGE.items.accounts.length; i++) {
                    otherAccount = this.PAGE.items.accounts[i];
                    if (otherAccount.userCheckStates.duplicate) {

                        /* because of forward iteration nature of this, this
                                has been cleared and marked as a set for another item */
                        continue;
                    }
                    this.checkAccountForDuplicateLocals(otherAccount);
                }
            },

            /**
            * Returns Boolean defining whether account username is considered reserved.
            *
            * @method isReservedUsername
            * @param acct {Object} angular user account object
            * @return {Boolean} true if username is reserved
            */
            isReservedUsername: function isReservedUsername(acct) {
                var username = this.getUserNameFromAcct(acct);

                /* trim spaces from ends of username */
                var trimmedUsername = username.replace(/^\s*(.+)\s*$/i, "$1");

                /* check against reserved system names to see if this on exists */
                if (trimmedUsername in this.reservedUsernames) {
                    return true;
                }

                /* interim list of restricted partial names (reg ex patterns) */
                /* list cannot contain these specific parts */
                /*
                        matches names, or parts of names dependent on need
                        <[name]>$ matches a <[name]> at the end of a username
                        ^<[name]> matches a <[name]> at the beginning of the username
                        ^<[name]>$ matches exactly that <[name]> with no trailing or begining characters
                    */

                var currentRegExp, reservedNamePattern;
                for (var i = 0; i < this.reservedUsernamePatterns.length; i++) {
                    reservedNamePattern = this.reservedUsernamePatterns[i];

                    /* build dynamic regular expression */
                    currentRegExp = new RegExp(reservedNamePattern, "gi");
                    if (trimmedUsername.match(currentRegExp) !== null) {
                        return true;
                    }
                }

                return false;

            },

            /**
            * Returns Boolean representing whether acct.username exists on local machine
            * in part or fully (only first USERNAME_UNIQUE_LENGTH characters need to match)
            *
            * @method isExistingLocalUser
            * @param acct {Object} angular user account object
            * @return {Boolean} dependent on user existing on local server
            */
            isExistingLocalUser: function isExistingLocalUser(acct) {
                var username = this.getUserNameFromAcct(acct);
                var trimmedUsername = this.makeUsernamePartial(username, true);
                if (trimmedUsername in this.localPartialUsernames) {
                    acct.similarLocalUser = this.localPartialUsernames[trimmedUsername];
                    return true;
                }

                return false;
            },

            /**
            * Tests username against globally established regexp
            * uses the transfer specific regexp if remote_user === localuser
            * uses the non-transfer regexp otherwise
            *
            * @method isLocalUsernameValid
            * @param acct {Object} angular user account object
            * @return {Boolean} true or false based on regexp.test
            */
            isLocalUsernameValid: function isLocalUsernameValid(acct) {
                var re = this.getUsernamePattern("TRANSFER_USER_RESTRICT");
                var partial = this.makeUsernamePartial(acct.localuser, true);
                // eslint-disable-next-line no-useless-escape
                if (!partial.replace(/\-/gi, "").length) {
                    return false;
                }
                return re.test(acct.localuser);
            },

            makeUsernamePartial: function makeUsernamePartial(username, removeSpecialCharacters) {
                if (removeSpecialCharacters) {
                    // eslint-disable-next-line no-useless-escape
                    username = username.replace(/[\_\.]/gi, "");
                }
                return username.replace(this.getUsernamePattern("TRIM_PATTERN"), "$1").toLowerCase();
            },

            /**
             * Get the classes for each account row
             *
             * @param {object} account user account to check against
             * @returns {string} if the item is selected, and either the domain or user is invalid, else nothing
             */
            getAccountRowClasses: function getAccountRowClasses(account) {
                if (!account.selected) {
                    return "";
                }

                if (!account.invalidUser && !account.invalidDomain) {
                    return "success";
                }

                return "danger";
            },

            /**
             * Determine whether a column should show based on the key
             *
             * @param {string} columnName account key to check
             * @returns {boolean} qwhether to show the column
             *
             */
            showColumn: function showColumn(columnName) {
                switch (columnName) {
                    case "bytesused":
                        return !!this.PAGE.remote.has_disk_used;
                    case "owner":
                        return !!this.PAGE.remote.has_owners;
                    case "dedicated_ip":
                        return !!this.showDedicatedIPColumn;
                    default:
                        return true;
                }
            },

            /**
             * For Each account, determine the current chevron icon state
             *
             * @param {*} account account to check
             * @returns {string} if the account is expanded, 'fa-chevron-down', else a left or right based on the RTL settings of LOCALE
             */
            getChevronClasses: function getChevronClasses(account) {
                var collapsedClass = this.isRTL ? "fa-chevron-left" : "fa-chevron-right";
                return this.isAccountExpanded(account) ? "fa-chevron-down" : collapsedClass;
            },

            /**
             * Update the isCustomized value for an account based on skipOptions states
             *
             * @param {object} account account to check
             */
            updateCustomizedFlag: function updateCustomizedFlag(account) {
                account.isCustomized = this._skipOptionsAltered(account) || this._workerOptionAltered(account) || this._proxyOptionAltered(account);
            },

            _skipOptionsAltered: function _skipOptionsAltered(account) {
                var skipKeys = Object.keys(SKIP_FLAG_DEFAULTS);
                for (var i = 0; i < skipKeys.length; i++) {
                    var skipKey = skipKeys[i];
                    if (account[skipKey] !== SKIP_FLAG_DEFAULTS[skipKey]) {
                        return true;
                    }
                }
                return false;
            },

            /**
             * Check if Live Transfer option has be altered
             *
             * @param  {object} account account to check
             */
            _proxyOptionAltered: function _proxyOptionAltered(account) {
                if (account.proxyOption.value !== account.proxyOption.default) {
                    return true;
                }
                return false;
            },

            /**
             * Check if the account is expanded
             *
             * @param {object} account account to check
             * @returns {boolean} true|false state of account expansion
             */
            isAccountExpanded: function isAccountExpanded(account) {
                return this.expandedAccount === account;
            },

            /**
             * Expand the account
             *
             * @param {object} account account to expand
             */
            expandAccount: function expandAccount(account) {
                if (this.expandedAccount) {
                    this.collapseAccount(this.expandedAccount);
                }
                this.expandedAccount = account;
                this.accountSettingUpdated(account, true);
            },

            /**
             * Collapse the account
             *
             * @param {object} account account to collapse
             */
            collapseAccount: function collapseAccount(account) {
                this.expandedAccount = false;
            },

            /**
             * Toggle the expanded state of an account
             *
             * @param {object} account account to toggle
             */
            toggleAccountExpansion: function toggleAccountExpansion(account) {
                if ( this.isAccountExpanded(account) ) {
                    this.collapseAccount(account);
                } else {
                    this.expandAccount(account);
                }
            },

            /**
             * Get the label based on the isCustomized value of the account
             *
             * @param {object} account account to check
             */
            getCustomizeLabel: function getCustomizeLabel(account) {
                return account.isCustomized ? CUSTOM_CUSTOMIZED_LABEL : DEFAULT_CUSTOMIZED_LABEL;
            },

            /**
             * Called from the view when the expanded panel of an account change
             *
             * @param {object} account that changed
             * @param {string} key what option changed
             * @param {*} value what is the new value of that option
             */
            onExpandPanelOptionChanged: function onExpandPanelOptionChanged(account, key, value) {
                this.updateAccountSetting(account, key, value);
            },

            /**
             * Called from the view when "apply to all" is emmitted
             *
             * @param {object} fromAccount source account to copy from
             * @param {object[]} toAccounts destination accounts to copy to
             * @param {object[]} skipOptions which skip options to update
             * @param {object} workerOptions which worker options to update
             * @param {object} proxyOption proxy option to update
             */
            onExpandPanelApplyToAll: function onExpandPanelApplyToAll(fromAccount, toAccounts, skipOptions, workerOptions, proxyOption) {

                // Get Skip Model Keys Once
                var skipModelKeys = skipOptions.map(function(skipOption) {
                    return skipOption.modelKey;
                }, this);

                // Get Worker Model Keys Once
                var workerModelKeys = workerOptions && Object.keys(workerOptions).map(function(workerOptionType) {
                    return workerOptions[workerOptionType].modelKey;
                }, this) || [];

                // Include other options
                var modelKeys = ["dedicated_ip", "copy_proxy_option"].concat(skipModelKeys, workerModelKeys);

                var copyOverwrite = this.canNeedOverwrite(fromAccount);

                // Update extra items and validate
                toAccounts.filter(function(toAccount) {
                    if (toAccount === fromAccount) {
                        return false;
                    }
                    return true;
                }).forEach(function(toAccount) {
                    var myCopyOverwrite = copyOverwrite && this.canNeedOverwrite(toAccount);

                    var myModelKeys = modelKeys.slice();
                    if (myCopyOverwrite) {
                        myModelKeys.push("overwrite_type");
                    }

                    myModelKeys.forEach(function(modelKey) {
                        this.updateAccountSetting(toAccount, modelKey, fromAccount[modelKey], false);
                    }, this);

                    // If, but only if, both accounts are need-overwrite
                    // we should copy the overwrite setting.
                    if (myCopyOverwrite) {
                        this.updateOverwriteFlags(toAccount, false);
                    }

                    this.validateAccount(toAccount);
                }, this);
            },

            /**
             * Update an account setting and update settings based on it.
             *
             * @param {object} account account on which to update the setting
             * @param {string} key setting to update
             * @param {*} value new value
             * @param {boolean} validate validate after update
             */
            updateAccountSetting: function updateAccountSetting(account, key, value, validate) {
                if (!validate && key === "copy_proxy_option") {
                    account.proxyOption.value = value;
                }
                account[key] = value;
                this.accountSettingUpdated(account, validate);
            },

            /**
             * Called when any account setting is updated. Optionally validates the account based on state.
             *
             * @param {object} account account that had the update occur
             * @param {boolean} validate when true, validateAccount() will be called
             */
            accountSettingUpdated: function accountSettingUpdated(account, validate, skipForceSelect) {
                var callUpdate;
                if (!skipForceSelect && !account.selected) {
                    account.selected = 1;
                    callUpdate = true;
                }
                this.updateCustomizedFlag(account);
                if (validate) {
                    this.validateAccount(account);
                }
                if (callUpdate) {
                    this.updateSelectedAccounts();
                }
            },

            /**
             * Set a function to call when the selected accounts change
             *
             * @param {function} func function to call when the selected accounts change
             */
            setUpdateSelectedAccountsFunction: function setUpdateSelectedAccountsFunction(func) {
                this._updateSelectedAccounts = func;
            },

            /**
             * Called when selected accounts change, if set by setUpdateSelectedAccountsFunction() a callback function will be called too
             *
             */
            updateSelectedAccounts: function updateSelectedAccounts() {
                if (this._updateSelectedAccounts) {
                    this._updateSelectedAccounts();
                }
            },

            /**
             * Called by the view when an accounts selection changes
             *
             * @param {object} account the account that changed. Unused by the function.
             */
            accountSelectionUpdated: function accountSelectionUpdated(account) {
                this.updateSelectedAccounts();
            },

            /**
             * Check if an account is eligible for the overwrite dropdown
             *
             * @param {object} account account to be checked
             * @returns {boolean} whether or not the account could ever need overwriting
             */
            canNeedOverwrite: function canNeedOverwrite(account) {
                var localUsers = this.PAGE.local.users;
                var localDomains = this.PAGE.local.domains;
                return localUsers[account.user] || localUsers[account.localuser] || (localDomains[account.domain] === account.localuser);
            },

            /**
             * Update the specific overwrite flags based on the overwrite_type of the account
             * accountSettingUpdate is then called, passing along the validate value
             *
             * @param {object} account account to be updated
             * @param {boolean} validate whether to validate during the accountSettingUpdated phase
             */
            updateOverwriteFlags: function updateOverwriteFlags(account, validate, skipForceSelect) {
                account.overwrite_account = 0;
                account.overwrite_with_delete = 0;
                switch (account.overwrite_type.value) {
                    case this.overwriteStates.OVERWRITE_WITH_DELETE:
                        account.overwrite_with_delete = 1;

                    // fall through here is intentional as we want it to set overwrite_account as well when we set overwrite_with_delete
                    // eslint-disable-next-line no-fallthrough
                    case this.overwriteStates.OVERWRITE:
                        account.overwrite_account = 1;
                        break;
                }
                this.accountSettingUpdated(account, validate, skipForceSelect);
            },

            openOverwriteDescriptionModal: function openOverwriteDescriptionModal() {
                var self = this;
                self.overwriteModal = this.openModal({
                    templateUrl: this.overwriteDescriptionTemplate,
                    controller: ["$scope", function($scope) {
                        $scope.close = function() {
                            self.closeOverwriteDescriptionModal();
                        };
                    }]
                });
            },

            closeOverwriteDescriptionModal: function closeOverwriteDescriptionModal() {
                if (this.overwriteModal) {
                    this.overwriteModal.close();
                    this.overwriteModal = null;
                }
            }

        });

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
            app.value("PAGE", PAGE);
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        AccountTableController.$inject = CONTROLLER_INJECTABLES;
        var controller = app.controller("AccountTableController", AccountTableController);

        return controller;

    }
);
