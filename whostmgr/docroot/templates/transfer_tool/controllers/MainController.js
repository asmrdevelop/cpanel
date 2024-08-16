/*
# cpanel - templates/transfer_tool/controllers/MainController.js
#                                               Copyright(c) 2021 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W003 */
/**
 * @class Class constructor for the main controller
 * @param {object} $scope
 * @param {object} $filter
 */


define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/directives/pageSizeDirective",
        "../filters/startFromFilter",
        "../filters/cpLimitToFilter",
    ],
    function(angular, LOCALE) {

        "use strict";

        var CONTROLLER_INJECTABLES = ["$scope", "$log", "$filter", "PAGE", "OVERWRITE_OPTIONS", "OVERWRITE_STATES"];

        var MainController = function($scope, $log, $filter, PAGE, OVERWRITE_OPTIONS, OVERWRITE_STATES) {

            var _this = this;

            _this._log = $log;
            _this.PAGE = PAGE;
            _this.REMAINING_ACCOUNT_SLOTS = parseInt(PAGE.REMAINING_ACCOUNT_SLOTS, 10);
            _this.SERVER_MAX_USERS = parseInt(PAGE.SERVER_MAX_USERS, 10);
            _this.pkgTable = {
                currentPage: 1,
                pageSize: 10,
                reverse: false,
                order: "name",
            };

            _this.overwriteStates = OVERWRITE_STATES;

            // Determine if cPanel version is less than 11.55.
            _this.olderRemote = parseInt(_this.PAGE.remote.version.split(".")[1]) < 55;

            var serverType = LOCALE.maketext("Unknown");

            if (_this.PAGE.remote.server_type.match(/WHM/)) {
                serverType = "WHM " + _this.PAGE.remote.version;
            } else {
                serverType = _this.PAGE.remote.server_type + " " + _this.PAGE.remote.version;
            }
            var isCpanel = true;
            if ( !serverType.match(/WHM/) ) {
                isCpanel = false;
            }

            _this.meta = {
                server_type: serverType,
                is_cpanel: isCpanel,
                panel_name: _this.PAGE.remote.server_type,
            };

            _this.LOCALE = LOCALE;

            // Set default values - this checks them
            _this.control_bwdata = true;
            _this.control_homedir = true;
            _this.control_databases = true;
            _this.control_reseller_privs = true;

            // Packages / Main
            angular.forEach(_this.PAGE.items.packages, function(val, key) {
                _this.PAGE.items.packages[key].selected = 0;
            });

            _this.PAGE.domainsWithDedicatedIp = {};

            angular.forEach(_this.PAGE.local.dedicated_ips, function(value, key) {
                this[value] = true;
            }, _this.PAGE.domainsWithDedicatedIp);


            var startFrom = $filter("startFrom"),
                orderBy = $filter("orderBy"),
                limitTo = $filter("cpLimitTo"),
                filter = $filter("filter");

            _this.existingUsersFilter = $filter("existingUsers");

            _this.selectedAccounts = filter(_this.PAGE.items.accounts, {
                selected: 1,
            });

            _this.selectedPackages = filter(_this.PAGE.items.packages, {
                selected: 1,
            });

            // To better understand what these assignments are look at updateFilteredPackages and updateViewablePackages
            _this.filteredPackages = filter(_this.PAGE.items.packages, _this.pkgsFilter);
            _this.viewablePackages = limitTo(startFrom(orderBy(_this.filteredPackages, _this.pkgTable.order, _this.pkgTable.reverse), (_this.pkgTable.currentPage - 1) * _this.pkgTable.pageSize),
                _this.pkgTable.pageSize);

            /**
             * Updates the selectedPackages array based on what packages are selected
             */
            _this.updateSelectedPackages = function() {
                _this.selectedPackages = filter(this.PAGE.items.packages, {
                    selected: 1,
                });
            };

            _this.updateSelectedConfigurations = function() {
                _this.selectedConfigurations = [];
                angular.forEach(_this.PAGE.configuration_modules, function(value, key) {
                    if (value.selected) {
                        var config = {};
                        config[key + "_enabled"] = 1;
                        _this.selectedConfigurations.push( config );
                    }
                });
            };

            _this.updateSelectedConfigurations();

            /**
             * Dispatches Event to be caught by AccountTableController
             */
            _this.recheckUsers = function(dataset) {
                $scope.$broadcast("recheckUsersCalled", {
                    dataset: dataset,
                });
            };

            /**
             * Updates the selectedAccounts array based on what packages are selected
             */
            _this.updateSelectedAccounts = function() {
                _this.selectedAccounts = filter(this.PAGE.items.accounts, {
                    selected: 1,
                });
            };

            /**
             * Reapplies filters for the filteredPackages array
             * Array    ->    Filtered by pkgsFilter
             * packages | filter:pkgsFilter
             */
            _this.updateFilteredPackages = function() {
                _this.filteredPackages = filter(this.PAGE.items.packages, this.pkgsFilter);
            };

            /**
             * Reapplies filteres for the viewablePackages array.
             * FilteredPackages ->              Ordered by(reverse?)         ->          start at page# * pageSize                         ->    limit to page size
             * filteredPackages | orderBy: acctTable.order:acctTable.reverse | startFrom:(acctTable.currentPage - 1 ) * acctTable.pageSize | limitTo: acctTable.pageSize
             */
            _this.updateViewablePackages = function() {
                _this.viewablePackages = limitTo(startFrom(orderBy(_this.filteredPackages, _this.pkgTable.order, _this.pkgTable.reverse), (_this.pkgTable.currentPage - 1) * _this.pkgTable.pageSize),
                    _this.pkgTable.pageSize);
            };

            _this.getPossiblePageSizes = function() {
                return _this.PAGE.all_possible_page_sizes;
            };

            /**
             * Returns true if the source account is being assigned a new dedicated ip.
             * @param  {object} item Account object
             * @return {Boolean}
             */
            _this.newDedicatedIpFilter = function(item) {
                if (!item.dedicated_ip) {
                    return false;
                }

                return !_this.PAGE.domainsWithDedicatedIp[item.domain];
            };

            _this.toArray = function() {
                _this.configuration_modules = [];
                angular.forEach(_this.PAGE.configuration_modules, function(val, key) {
                    var analysis = [];
                    angular.forEach(val.analysis, function(analysisValue, analysisKey) {
                        analysis.push({ analysis: analysisValue, analysisKey: analysisKey });
                    });
                    val.analysis = analysis;
                    _this.configuration_modules.push({ key: key, value: val });
                });
            };

            _this.overwriteIsDefault = function overwriteIsDefault(item) {
                return item.overwrite_type.value === _this.overwriteStates.NO_OVERWRITE;
            };

            _this.overwriteOptions = OVERWRITE_OPTIONS;

            // If no viewable accounts are selected, make sure the checkbox is unchecked.
            $scope.$watch(function() {
                return _this.selectedAccounts.length;
            }, function(newVal) {
                if (!newVal) {
                    $scope.$broadcast("selectedAccountsEmptied", {});
                }
            });


            $scope.$watch(function() {
                return _this.pkgTable;
            }, function() {
                _this.updateViewablePackages();
            }, true);

            _this.toArray();

            return _this;
        };

        /**
         * Function that updates both filtered and viewable packages array results
         */
        MainController.prototype.updatePackages = function() {
            this.updateFilteredPackages();
            this.updateViewablePackages();
        };

        MainController.prototype.updateConfigurations = function() {
            this.updateSelectedConfigurations();
        };

        /**
         * Returns 'icon-arrow-up' or 'icon-arrow-down' if column is selected for ordering.  The result is based on what order.  Used to indicate sort order.
         * @param  {objec} tableOptionsObj
         * @param  {string} column
         * @return {string|Boolean}
         */
        MainController.prototype.selectedHeaderClass = function(tableOptionsObj, column) {
            var className = "icon-arrow-" + (tableOptionsObj.reverse ? "down" : "up");
            return column === tableOptionsObj.order && className;
        };

        /**
         * Returns 'active' if column is selected for ordering.  Used to highlight selected column.
         * @param  {object} tableOptionsObj
         * @param  {string} column
         * @return {string|Boolean}
         */
        MainController.prototype.selectedColClass = function(tableOptionsObj, column) {
            return column === tableOptionsObj.order && "active";
        };

        /**
         * Takes in an array of accounts and sets the attr of each account to a value of 1 or 0 corresponding to isChecked.  1 or 0 for Perl parsing after form submit.
         * @param  {array}  dataset
         * @param  {string}  attr
         * @param  {Boolean} isChecked
         */
        MainController.prototype.toggleCheckAll = function(dataset, attr, isChecked) {
            var newValue;
            if (attr === "overwrite_type") {
                newValue = isChecked;
            } else {
                newValue = isChecked ? 1 : 0;
            }
            angular.forEach(dataset, function(o) {
                o[attr] = newValue;
            });
        };

        MainController.prototype.toggleCheckAllAndReValidate = function(dataset, attr, isChecked) {
            var _this = this;
            _this.toggleCheckAll.apply(_this, arguments);

            /* selected accounts list must be updated before validation can occur */
            _this.updateSelectedAccounts();
            _this.recheckUsers(dataset);
        };

        /**
         * Sets the order and reverse attributes for tableOptions.  Used for column sorting.
         * @param  {object} tableOptionsObj
         * @param  {string} fieldName
         */
        MainController.prototype.toggleSort = function(tableOptionsObj, fieldName) {
            tableOptionsObj.reverse = (tableOptionsObj.order === fieldName ? !tableOptionsObj.reverse : 0);
            tableOptionsObj.order = fieldName;
        };


        /**
         * Returns true if the account is selected and has an invalid user
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.invalidUserFilter = function(item) {
            return item.selected && item.invalidUser;
        };


        /**
         * Returns true if the account's local name has not changed from the remote name.
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.noUsernameChange = function(item) {
            return item.localuser === item.remote_user;
        };


        /**
         * Returns true if the account matches a reserved account name on the file system
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.reservedUserFilter = function(item) {
            return item.selected && item.invalidUser && item.userCheckStates.reserved;
        };

        /**
         * Returns true if the account username matches another name selected for importation
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.duplicateUserFilter = function(item) {
            return item.selected && !!item.localuser && item.invalidUser && item.userCheckStates.duplicate;
        };

        /**
         * Returns true if the account does not match the system regular expression requirements
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.invalidUsernameFilter = function(item) {
            return item.selected && item.invalidUser && item.userCheckStates.invalid;
        };


        /**
         * Returns true if the account is selected and has an invalid domain.
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.invalidDomainFilter = function(item) {
            return item.selected && item.invalidDomain;
        };

        /**
         * Returns true if the account is selected, the user is a reseller on the source server,
         * and the reseller privileges are not being transferred.
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.resellerNoCopyFilter = function(item) {
            return item.selected && item.is_reseller && !item.copy_reseller_privs;
        };

        /**
         * Revalidates all account usernames in provided array
         * @param  {array} array
         */
        MainController.prototype.reValidateDomainAndUsernameFor = function(array) {
            if (!array) {
                return;
            }
            for (var x = 0; x < array.length; x++) {
                var username = array[x].localuser || "";
                if (!username.length) {
                    username = array[x].remote_user;
                }

                array[x].invalidUser = this.PAGE.local.users[username] && !array[x].invalidDomain && array[x].overwrite_type === this.overwriteOptions[0] ? 1 : 0;
            }
        };

        /**
         * Returns message based on the way in which an account matches a local account.
         * @param  {object} acct
         * @return {String}
         */
        MainController.prototype.getExistingUserMessage = function(acct) {

            var incomingLocal = acct.localuser;
            var matchedLocal = acct.similarLocalUser;

            if (incomingLocal === matchedLocal) {
                return this.LOCALE.maketext("The remote account “[_1]” cannot transfer because an account with the same username exists on the local server.", incomingLocal);
            } else {
                return this.LOCALE.maketext("The remote account “[_1]” cannot transfer because the first [quant,_3,non-special character matches,non-special characters match] the local username “[_2]”.", incomingLocal, matchedLocal, this.PAGE.USERNAME_UNIQUE_LENGTH);
            }

        };

        MainController.prototype.existingAccountWarning = function(acctCount) {
            return LOCALE.maketext("[output,strong,Error]: You have selected [quant,_1,account transfer,account transfers] that will not complete properly because the [numerate,_1,username,usernames] already [numerate,_1,exists,exist] on the local server.", acctCount) + " " +
                LOCALE.maketext("To resolve this, you can overwrite the local [numerate,_1,account,accounts], rename the incoming [numerate,_1,account,accounts], or deselect the [numerate,_1,account,accounts].", acctCount);
        };

        MainController.prototype.existingDomainWarning = function(domainCount) {
            return LOCALE.maketext("[output,strong,Error]: You have selected [quant,_1,account transfer,account transfers] that will not complete properly because of [numerate,_1,a domain conflict,domain conflicts].", domainCount) + " " +
                LOCALE.maketext("This is due to [numerate,_1,an existing domain,existing domains] that [numerate,_1,matches an incoming domain,match incoming domains] but [numerate,_1,does,do] not match the local [numerate,_1,username,usernames].", domainCount) + " " +
                LOCALE.maketext("To resolve this, remove the matching [numerate,_1,domain,domains] from the local machine for any [numerate,_1,account,accounts] that you wish to transfer.", domainCount);
        };

        MainController.prototype.dedicatedIpAddrWarning = function(ipsToAdd, availableIps) {
            return LOCALE.maketext("[output,strong,Error]: You have selected [numf,_1] of [quant,_2,available IP address,available IP addresses]. Either deselect an account to transfer, or deselect its corresponding “[_3]” field.", ipsToAdd, availableIps, LOCALE.maketext("Dedicated IP Address"));
        };

        MainController.prototype.frontPageWarning = function(fpAccts) {
            return LOCALE.maketext("[output,strong,Warning]: You selected [quant,_1,account,accounts] that use [asis,Microsoft® FrontPage Extensions] on the source server. The local server does not support [asis,FrontPage]. To resolve this issue, disable [asis,FrontPage] for each account before you attempt the transfer.", fpAccts);
        };

        MainController.prototype.unusedDedicatedIpWarning = function(unusedDedIpAcctCount) {
            return LOCALE.maketext("[output,strong,Warning]: You have selected [quant,_1,account,accounts] which previously had a dedicated [asis,IP] address but you have chosen not to assign one after transfer.", unusedDedIpAcctCount);
        };

        MainController.prototype.packageFilterMessage = function() {
            return (this.pkgsFilter) ?
                LOCALE.maketext("Your search matched [numf,_1] of [quant,_2,record,records].", this.filteredPackages.length, this.PAGE.items.packages.length) :
                LOCALE.maketext("There [numerate,_1,is,are] [quant,_1,record,records].",  this.PAGE.items.packages.length);
        };

        MainController.prototype.packageSelectedMessage = function() {
            return LOCALE.maketext("[_1] selected", this.selectedPackages.length || 0);// this.PAGE.items.packages | filter:{selected: 1}).length);
        };

        MainController.prototype.accountFilterMessage = function(acctCount) {
            return (acctCount !== this.PAGE.items.accounts.length) ?
                LOCALE.maketext("Your search matched [numf,_1] of [quant,_2,record,records].", acctCount || 0, this.PAGE.items.accounts.length) :
                LOCALE.maketext("There [numerate,_1,is,are] [quant,_1,record,records].",  this.PAGE.items.accounts.length);
        };

        MainController.prototype.accountSelectedMessage = function(acctCount) {
            return LOCALE.maketext("[quant,_1,account,accounts] selected.", acctCount || 0);
        };

        MainController.prototype.accountConflictSelectedMessage = function(count) {
            return LOCALE.maketext("You have selected [quant,_1,account,accounts] that cannot transfer properly because [numerate,_1,its username conflicts,their usernames conflict] with [numerate,_1,a username,usernames] on the local server.", count);
        };

        MainController.prototype.licenseOverloadMessage = function() {
            if (this.REMAINING_ACCOUNT_SLOTS === 0) {
                return LOCALE.maketext("Because the destination server’s license is limited to [quant,_1,account,accounts], you can only overwrite existing accounts.", this.SERVER_MAX_USERS);
            } else {
                return LOCALE.maketext("Because the destination server’s license is limited to [quant,_1,account,accounts], you can only transfer [quant,_2,account,accounts].", this.SERVER_MAX_USERS, this.REMAINING_ACCOUNT_SLOTS);
            }
        };

        MainController.prototype.licenseOverloadCancelMessage = function(count) {
            return LOCALE.maketext("Deselect [quant,_1,account,accounts] to continue.", count);
        };

        MainController.prototype.accountOverwriteResolveMessage = function(count) {
            return LOCALE.maketext("To resolve this issue, you can overwrite the local [numerate,_1,account,accounts], rename the incoming [numerate,_1,account,accounts] so that the first [quant,_2,alphanumeric character,alphanumeric characters] do not match those of any local accounts, or deselect the [numerate,_1,account,accounts]. These options are mutually exclusive.",
                count, this.PAGE.USERNAME_UNIQUE_LENGTH);
        };

        MainController.prototype.accountOverwriteConfirmMessage = function(count) {
            return LOCALE.maketext("Overwrite conflicted [numerate,_1,account,accounts]", count);
        };

        MainController.prototype.accountConflictCancelMessage = function(count) {
            return LOCALE.maketext("Deselect conflicted [numerate,_1,account,accounts]", count);
        };

        MainController.prototype.accountConflictResolveMessage = function(count) {
            return LOCALE.maketext("To resolve this issue, you can rename the incoming [numerate,_1,account,accounts] so that the first [quant,_2,alphanumeric character,alphanumeric characters] do not match those of any local accounts, or deselect the [numerate,_1,account,accounts].",
                count, this.PAGE.USERNAME_UNIQUE_LENGTH);
        };

        MainController.prototype.accountConflictSelectedResolveMessage = function(count) {
            return LOCALE.maketext("You have selected [quant,_1,account transfer,account transfers] that will not complete properly because the [numerate,_1,username is,usernames are] reserved on the local server. To resolve this, you can either rename the incoming [numerate,_1,account,accounts] or deselect the [numerate,_1,account,accounts].", count);
        };

        MainController.prototype.accountConflictNameResolveMessage = function(count) {
            return LOCALE.maketext("The following [quant,_1,remote user is set,remote users are set] to migrate with [numerate,_1,a new name,new names] whose first [quant,_2,character conflicts,characters conflict] with one or more other proposed new usernames. To resolve this, you can either rename the incoming [numerate,_1,account,accounts] or deselect [numerate,_1,it,them].",
                count, this.PAGE.USERNAME_UNIQUE_LENGTH);
        };

        MainController.prototype.accountRenameMessage = function(to, from) {
            return LOCALE.maketext("“[_1]” is set to be renamed “[_2]”.", to, from);
        };

        MainController.prototype.usernameValidationTitle = function(count) {
            return LOCALE.maketext("You have entered [quant,_1,username that does,usernames that do] not meet this server’s username requirements:", count);
        };

        MainController.prototype.usernameValidationMessage = function(count) {
            return LOCALE.maketext("Usernames must be no longer than [quant,_1,character,characters] and must contain only lowercase letters and numerals. They may not begin with a numeral. To resolve this, you can either fix the [numerate,_2,username,usernames] or deselect the [numerate,_1,account,accounts].",
                this.PAGE.MAX_USERNAME_LENGTH, count);
        };

        MainController.prototype.usernameValidationAction = function(count) {
            return LOCALE.maketext("Deselect the [numerate,_1,account,accounts] with [numerate,_1,the invalid username,invalid usernames].", count);
        };

        MainController.prototype.dedicatedIPDeselectAction = function(count) {
            return LOCALE.maketext("Deselect “Dedicated IP Address” for conflicted [numerate,_1,account,accounts]", count);
        };

        MainController.prototype.dedicatedIPReselectAction = function(count) {
            return LOCALE.maketext("Reselect “[_1]” for [numerate,_2,account,accounts]", LOCALE.maketext("Dedicated IP Address"), count);
        };

        MainController.prototype.domainsWithFrontpageMessage = function(count) {
            return LOCALE.maketext("The following domains use [asis,FrontPage] on the source server:");
        };

        MainController.prototype.resellerNoCopyTitle = function(count) {
            return LOCALE.maketext("You have selected [quant,_1,user,users] that will be transferred with no reseller privileges.", count);
        };

        MainController.prototype.resellerNoCopyMessage = function(count) {
            if (this.PAGE.restricted_restore) {
                return LOCALE.maketext("[numerate,_1,This user is a reseller,These users are resellers] on the source server. Restricted Restore does not allow the transfer of reseller privileges. After the system restores the [numerate,_1,user,users], you can assign reseller privileges in WHM’s Reseller Center interface ([output,em,WHM » Home » Resellers » Reseller Center]).", count);
            } else {
                return LOCALE.maketext("[numerate,_1,This user is a reseller,These users are resellers] on the source server. To transfer an account’s reseller privileges from the source server, edit the [output,strong,Transfer Configuration] for the desired [numerate,_1,account,accounts] above. Be aware that reseller privileges can give users special permissions, including full root access, to your server.", count);
            }
        };

        MainController.prototype.resellerNoCopyFixMessage = function(count) {
            return LOCALE.maketext("Transfer reseller privileges for the selected [numerate,_1,account,accounts].", count);
        };

        MainController.prototype.canSubmitForm = function(warningLists, dedicatedIPAccounts, newSelectedUserList) {

            // Do warnings exists for any of these view lists
            for (var i = 0; i < warningLists.length; i++) {
                if (warningLists[i].length) {
                    return false;
                }
            }

            // Check for selected items
            if (!this.selectedPackages.length && !this.selectedAccounts.length && !this.selectedConfigurations.length) {
                return false;
            }

            // Check for dedicated IP overages
            if (dedicatedIPAccounts.length > this.PAGE.local.available_ips.length) {
                return false;
            }

            // Check for Empty Slots
            if (this.SERVER_MAX_USERS && newSelectedUserList.length > this.REMAINING_ACCOUNT_SLOTS) {
                return false;
            }

            return true;
        };

        MainController.prototype.getCopyButtonLabel = function getCopyButtonLabel() {
            return LOCALE.maketext("Copy");
        };

        MainController.prototype.submitSummaryMessage = function() {
            var summaryItems = [];
            if (this.selectedAccounts.length) {
                summaryItems.push(LOCALE.maketext("[quant,_1,Account,Accounts]", this.selectedAccounts.length));
            }
            if (this.selectedPackages.length) {
                summaryItems.push(LOCALE.maketext("[quant,_1,Package,Packages]", this.selectedPackages.length));
            }

            if (this.selectedConfigurations.length) {
                summaryItems.push(LOCALE.maketext("[quant,_1,Server Configuration,Server Configurations]", this.selectedConfigurations.length));
            }
            return LOCALE.maketext("When you click [output,em,_1], you will start the transfer process for the following: [list_and,_2]", this.getCopyButtonLabel(), summaryItems);
        };

        var app;
        try {
            app = angular.module("App"); // For runtime
            app.value("PAGE", PAGE);
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Returns true if the account does not exist locally on the server
         * @param  {object} item
         * @return {Boolean}
         */
        app.filter("existingUsers", function() {
            return function(items, exactMatchesOnly) {
                var matched = [];
                angular.forEach(items, function(item, index) {
                    if (exactMatchesOnly && item.localuser !== item.similarLocalUser) {

                        /* if exactMatchOnly is set, it will not return n character matches */
                        /* this is to allow filtering items to show only overwritable ones (exact matches) */
                        return false;
                    } else if (!exactMatchesOnly && item.localuser === item.similarLocalUser) {
                        return false;
                    }

                    /* will not return if user is also reserved because a reserved name overrides an existing name in transfers */
                    if (item.selected && item.invalidUser && item.userCheckStates.existing && !item.userCheckStates.reserved) {
                        matched.push(item);
                    }

                });
                return matched;
            };
        });

        MainController.$inject = CONTROLLER_INJECTABLES;
        var controller = app.controller("MainController", MainController);

        return controller;
    }
);
