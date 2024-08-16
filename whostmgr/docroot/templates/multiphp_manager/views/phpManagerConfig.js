/*
 * templates/multiphp_manager/views/phpManagerConfig.js
 *                                                 Copyright 2022 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* eslint no-use-before-define: 0*/

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/util/table",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "app/services/configService",
        "app/views/impactedDomainsPopup",
        "app/views/poolOptions"
    ],
    function(angular, _, LOCALE, PARSE, Table) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "phpManagerController",
            ["$scope", "$rootScope", "$q", "configService", "$timeout", "$uibModal", "alertService", "PAGE", "$interval",
                function($scope, $rootScope, $q, configService, $timeout, $uibModal, alertService, PAGE, $interval) {

                    $rootScope.$on("returnToDomainList", function() {
                        $rootScope.editPoolOptionsMode = false;

                        if (PAGE.poolOptionsDisplayMode) {
                            delete PAGE.poolOptionsDisplayMode;
                        }
                    });
                    $rootScope.litespeedRunning = PARSE.parsePerlBoolean(PAGE.litespeed_running);

                    var altRegex = /^alt/;
                    var eolWarningMsgLastPart = LOCALE.maketext("We recommend that you update to a supported version of [asis,PHP]. [output,url,_1,Learn more about supported versions,target,_2].", "http://php.net/supported-versions.php", "_blank");

                    $scope.actions = {
                        initialDataLoading: true,
                        loadingFPMInfo: false,
                        fetchingImpactedDomains: false,
                        settingSystemPHP: false,
                        fpmConversionRunning: false,
                        fpmConversionRunningOnLoad: false,
                        loadingAccountList: false
                    };

                    $scope.php = {
                        versions: [],
                        versionsInherit: [],
                        systemDefault: {
                            version: "",
                            displayVersion: "",
                            hasFPMInstalled: false,
                            showEolMsg: false,
                            eolWarningMsg: LOCALE.maketext("[output,strong,Warning]: Your system’s [asis,PHP] version has reached [output,acronym,EOL,End Of Life].") + " " + eolWarningMsgLastPart
                        },
                        showEolMsg: false,
                        eolWarningMsg: "",
                        perDomain: {
                            selected: ""
                        },
                        accountList: [],
                        compatibleVersions: [],
                        installedVersion: [],
                        systemEditView: false,
                        totalSelectedDomains: 0,
                        paginationMessage: "",
                        inheritWarning: LOCALE.maketext("[asis,PHP-FPM] option is disabled when one or more selections contain PHP version of [output,em,inherit]."),
                        incompatibleWarning: LOCALE.maketext("[asis,PHP-FPM] option is disabled when one or more selections contain PHP version that doesn’t have corresponding [asis,PHP-FPM] package installed."),
                        noVersions: false,
                    };

                    $scope.fpm = {
                        completePackageData: [],
                        checkingFPMPackage: false,
                        fpmPackageNeeded: false,
                        flag: false,
                        showMemoryWarning: false,
                        systemStatus: false,
                        requiredMemoryAmount: 0,
                        ea4ReviewLink: "",
                        fcgiMissing: false,
                        ea4Went: false,
                        conversionTimer: null,
                        conversionTimerInterval: 3000,
                        convertBuildId: null,
                        fpmConversionStarted: false,
                        domainSelection: 0,
                        missingPackages: [],
                        fpmWarning: LOCALE.maketext("The [output,em,inherit] option of [asis,PHP] Version is disabled when one or more selections have [asis,PHP-FPM] on.")
                    };

                    $scope.applyingPHPVersionTo = [];

                    var domainTable = new Table();

                    // Add more pageSizes.
                    domainTable.meta.pageSizes = _.concat(domainTable.meta.pageSizes, [500, 1000]);

                    var searchByDomainOrAccount = function(account, searchExpression) {
                        searchExpression = searchExpression.toLowerCase();

                        return account.account.toLowerCase().indexOf(searchExpression) !== -1 ||
                        account.vhost.toLowerCase().indexOf(searchExpression) !== -1 || account.account_owner.toLowerCase().indexOf(searchExpression) !== -1;
                    };

                    domainTable.setSearchFunction(searchByDomainOrAccount);
                    domainTable.setSort("vhost,account,account_owner,version,php_fpm", "asc");

                    $scope.meta = domainTable.getMetadata();

                    $scope.getFPMInfo = function() {
                        return getFPMInfo();
                    };

                    $scope.setFPMFlag = function() {
                        $scope.fpm.flag = false;
                        return configService.setFPMFlag();
                    };

                    $scope.editSystemPHP = function(toEditMode) {
                        if (toEditMode) {
                            $scope.php.systemEditView = true;
                            $scope.impactedDomains = {};
                            preSelectSystemValue();
                            processImpactedDomains("system_default", true, $scope.impactedDomains, true);
                        } else {
                            $scope.php.systemEditView = false;
                        }
                    };

                    $scope.applySystemPHP = function() {
                        return setSystemPHPVersion($scope.php.systemDefault.selected);
                    };

                    $scope.requiredMemory = function() {
                        return LOCALE.maketext("Your system requires [format_bytes,_1] of memory to convert the remaining domains to [asis,PHP-FPM].", $scope.fpm.requiredMemoryAmount);
                    };

                    $scope.switchSystemFPM = function() {
                        $scope.fpm.systemStatus = !$scope.fpm.systemStatus;
                        var status = $scope.fpm.systemStatus ? 1 : 0;
                        switchSystemFPM(status);
                    };

                    $scope.convertAllAccountsToFPM = function() {
                        return convertAllAccountsToFPM();
                    };

                    var addImpactedDomainsTo = function(vhost) {
                        if (typeof vhost.impactedDomains === "undefined") {
                            vhost.impactedDomains = {};
                        }

                        processImpactedDomains("domain", vhost.vhost, vhost.impactedDomains, vhost.selected);
                    };

                    $scope.handleEntireListSelection = function() {
                        var areAllSelected = domainTable.areAllDisplayedRowsSelected();
                        if (areAllSelected) {
                            domainTable.unselectAllDisplayed();
                        } else {
                            domainTable.selectAllDisplayed();
                        }
                        $scope.php.totalSelectedDomains = domainTable.getTotalRowsSelected();
                        $scope.php.accountList = domainTable.getList();
                    };

                    $scope.handleSingleListSelection = function(vhost) {
                        addImpactedDomainsTo(vhost);
                        if (vhost.selected) {
                            domainTable.selectItem(vhost);
                        } else {
                            domainTable.unselectItem(vhost);
                        }
                        $scope.php.allRowsSelected = domainTable.areAllDisplayedRowsSelected();
                        $scope.php.totalSelectedDomains = domainTable.getTotalRowsSelected();
                        $scope.php.accountList = domainTable.getList();
                    };

                    $scope.searchByDomainOrAccount = function() {
                        domainTable.update();

                        $scope.php.accountList = domainTable.getList();
                        $scope.meta = domainTable.getMetadata();
                        $scope.php.paginationMessage = domainTable.paginationMessage();
                    };

                    $scope.areRowsSelected = function() {
                        var rowsSelected = domainTable.getTotalRowsSelected();

                        if (rowsSelected === 0) {
                            return true;
                        } else {
                            return false;
                        }
                    };

                    $scope.applyPHPToMultipleAccounts = function() {
                        var version = $scope.php.perDomain.selected.version;
                        var vhostList = [];

                        var domains = domainTable.getSelectedList();
                        domains.forEach(function(domain) {
                            vhostList.push(domain.vhost);
                        });

                        $scope.php.accountList = domainTable.getList();

                        return applyPHPVersionToAccounts(version, vhostList);
                    };

                    $scope.applyPHPToSingleAccount = function(account) {
                        if (account.version === "inherit" && account.php_fpm) {
                            var version = account.display_php_version.split(" ")[2];
                            var endPoint = version.length - 2;
                            account.version = version.substr(1, endPoint);
                            return;
                        }
                        var vhostList = [];
                        vhostList.push(account.vhost);
                        applyPHPVersionToAccounts(account.version, vhostList);
                    };

                    $scope.isAnyDomainInherited = function() {
                        var accounts = domainTable.getSelectedList();
                        for (var i = 0, len = accounts.length; i < len; i++) {
                            if (accounts[i].inherited) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.isAnyDomainFPM = function() {
                        var accounts = domainTable.getSelectedList();
                        for (var i = 0, len = accounts.length; i < len; i++) {
                            if (accounts[i].php_fpm) {
                                return true;
                            }
                        }
                        return false;

                    };

                    $scope.updateTable = function() {
                        domainTable.update();
                        $scope.php.accountList = domainTable.getList();
                        $scope.meta = domainTable.getMetadata();
                        $scope.php.paginationMessage = domainTable.paginationMessage();
                    };

                    $scope.isAnyDomainIncompatible = function() {
                        var accounts = domainTable.getSelectedList();
                        var compatibleVersions = [];
                        $scope.php.compatibleVersions.forEach(function(version) {
                            version = version.split("-php-fpm")[0];
                            compatibleVersions.push(version);
                        });
                        for (var i = 0, len = accounts.length; i < len; i++) {
                            if (compatibleVersions.indexOf(accounts[i].version) === -1) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.isDomainVersionIncompatible = function(domainVersion) {

                        // always return false if domainVersion is "inherit"
                        if (domainVersion === "inherit") {
                            return false;
                        }

                        var compatibleVersions = [];
                        $scope.php.compatibleVersions.forEach(function(version) {
                            version = version.split("-php-fpm")[0];
                            compatibleVersions.push(version);
                        });

                        for (var i = 0, len = compatibleVersions.length; i < len; i++) {
                            if (domainVersion === compatibleVersions[i]) {
                                return false;
                            }
                        }
                        return true;
                    };

                    $scope.setMultipleDomainFPM = function() {
                        $scope.actions.applyingFPM = true;
                        var vhostList = [];
                        var selectedAccounts = domainTable.getSelectedList();

                        selectedAccounts.forEach(function(account) {
                            vhostList.push(account.vhost);
                        });
                        return applyDomainFPM($scope.fpm.domainSelection, vhostList);
                    };

                    $scope.setSingleDomainFPM = function(domain) {
                        var domainValue = domain.php_fpm ? 0 : 1;
                        var vhostList = [];
                        vhostList.push(domain.vhost);
                        return applyDomainFPM(domainValue, vhostList);
                    };

                    $scope.showAllImpactedDomains = function() {
                        var modalData = $scope.impactedDomains;
                        $uibModal.open({
                            templateUrl: "impactedDomainsPopup.ptt",
                            controller: "impactedDomainsPopup",
                            resolve: {
                                data: function() {
                                    return modalData;
                                }
                            }
                        });
                    };

                    $scope.setPoolOptionsDisplayValues = function(vhost) {
                        PAGE.poolOptionsDisplayMode = "domain";
                        PAGE.selectedDomainHomeDir = vhost.homedir;
                        PAGE.selectedDomainDocRoot = vhost.documentroot;
                        PAGE.selectedDomainName = vhost.vhost;
                        $rootScope.editPoolOptionsMode = true;
                    };

                    var getPHPVersions = function() {
                        return configService
                            .fetchPHPVersions()
                            .then(function(results) {
                                $scope.php.versions = createPHPDisplayVersions(results);
                                $scope.php.versionsInherit = createPHPVersionListInherit($scope.php.versions);
                            })
                            .catch(function(error) {

                                // No PHP version error is displayed as callout, so it does not also need to be an alert
                                if (error.indexOf("“PHP” is not installed on the system") === -1) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "getPHPVersionsError"
                                    });
                                }
                            });
                    };

                    var getSystemPHP = function() {
                        return configService.fetchSystemPhp()
                            .then(function(results) {
                                $scope.php.systemDefault.version = results.version;
                                $scope.php.systemDefault.displayVersion = configService.transformPhpFormat(results.version);
                            })
                            .catch(function(error) {

                                // No PHP version error is displayed as callout, so it does not also need to be an alert
                                if (error.indexOf("“PHP” is not installed on the system") === -1) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "getSystemPHPError"
                                    });
                                }
                            });
                    };


                    var validatePoolOption = function(input, max) {
                        var value = parseInt(input, 10);
                        if (isNaN(value)) {
                            return false;
                        } else if (value <= 0) {
                            return false;
                        } else if (value > max) {
                            return false;
                        }
                        return true;
                    };

                    var savePoolOptions = function(vhost) {
                        return configService.savePoolOption(vhost)
                            .then(function(data) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully updated the pool options for the domain “[_1]”.", vhost.vhost),
                                    autoClose: 5000,
                                    id: "poolOptionsSuccessMessage-" + vhost.vhost
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("Failed to apply [asis,PHP-FPM] Pool options to the selected domain."),
                                    closeable: true,
                                    id: "poolOptionsError"
                                });
                            })
                            .finally(function() {
                                getAccountList();
                            });
                    };

                    var applyDomainFPM = function(domainValue, selectedVhostList) {
                        $scope.actions.applyingFPM = true;
                        return configService.applyDomainFpm(domainValue, selectedVhostList)
                            .then(function(data) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully updated the [asis,PHP-FPM] setting."),
                                    autoClose: 5000,
                                    id: "phpFPMSuccessMessage"
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    id: "domainFPMError"
                                });
                            })
                            .finally(function() {
                                $scope.actions.applyingFPM = false;
                                getAccountList();
                            });
                    };

                    var applyPHPVersionToAccounts = function(version, vhostList) {
                        $scope.actions.applyingPHPVersion = true;
                        $scope.applyingPHPVersionTo = vhostList.slice();
                        return configService.applyDomainSetting(version, vhostList)
                            .then(function(data) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully updated the [asis,PHP] version to “[_1]”.", version),
                                    autoClose: 5000,
                                    id: "phpDomainSuccessMessage"
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    id: "domainVersionError"
                                });
                            })
                            .finally(function() {

                                // add a little delay so updating message is easier to read
                                $timeout(function() {
                                    $scope.actions.applyingPHPVersion = false;
                                    $scope.applyingPHPVersionTo = [];
                                }, 500);
                                getAccountList();
                            });
                    };

                    $scope.phpConversionInProgressFor = function(acct) {
                        return $scope.applyingPHPVersionTo.indexOf(acct) !== -1;
                    };

                    $scope.processInProgress = function() {
                        return $scope.actions.loadingAccountList ||  $scope.actions.applyingPHPVersion ||  $scope.actions.applyingFPM ||  $scope.fpm.fpmConversionStarted;
                    };

                    var convertAllAccountsToFPM = function() {
                        $scope.fpm.fpmConversionStarted = true;
                        return configService.convertAllAccountsToFPM()
                            .then(function(data) {
                                $scope.fpm.convertBuildId = data.build;
                                return monitorConversionStatus();
                            })
                            .catch(function(error) {
                                if (error === "canceled") {
                                    $scope.fpm.conversionTimer = null;
                                } else {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "convertAllAccountsError"
                                    });
                                }
                            })
                            .finally(function() {
                                $scope.fpm.fpmConversionStarted = false;
                                getAccountList();
                            });
                    };

                    var switchSystemFPM = function(newStatus) {
                        return configService.switchSystemFPM(newStatus)
                            .then(function(data) {
                                fetchFPMSystemStatus();
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "fpmSystemSwitchError"
                                });
                            });
                    };

                    var fetchFPMSystemStatus = function() {
                        return configService.fetchFPMStatus()
                            .then(function(data) {
                                $scope.fpm.systemStatus = PARSE.parsePerlBoolean(data.default_accounts_to_fpm);
                            });
                    };

                    var monitorConversionStatus = function() {
                        $scope.fpm.conversionTimer = $interval(function() {
                            configService.conversionInProgress()
                                .then(function(inProgress) {
                                    $scope.actions.fpmConversionRunning = inProgress;
                                    if (!inProgress) {
                                        $scope.actions.fpmConversionRunning = false;
                                        $scope.actions.fpmConversionRunningOnLoad = false;
                                        $interval.cancel($scope.fpm.conversionTimer);
                                    }
                                });
                        }, $scope.fpm.conversionTimerInterval);
                        return $scope.fpm.conversionTimer;
                    };

                    var setSystemPHPVersion = function(phpVersion) {
                        $scope.actions.settingSystemPHP = true;
                        alertService.clear();
                        return configService.applySystemSetting(phpVersion.version)
                            .then(function(data) {
                                if (data !== undefined) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("The system default [asis,PHP] version has been set to “[_1]”.", phpVersion.displayVersion),
                                        autoClose: 10000,
                                        id: "phpSystemSuccess"
                                    });
                                    $scope.php.systemDefault.version = phpVersion.version;
                                    $scope.php.systemDefault.displayVersion = configService.transformPhpFormat(phpVersion.version);
                                    $scope.php.toggleEolWarning("systemDefault", isPhpEol($scope.php.systemDefault.version));
                                }

                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "phpSystemError"
                                });
                            })
                            .finally(function() {
                                runFPMPackageCheck($scope.fpm.completePackageData);
                                $scope.php.systemEditView = false;
                                $scope.actions.settingSystemPHP = false;
                                getAccountList();
                            });
                    };

                    var preSelectSystemValue = function() {
                        for (var i = 0, len = $scope.php.versions.length; i < len; i++) {
                            if ($scope.php.versions[i].version === $scope.php.systemDefault.version) {
                                $scope.php.systemDefault.selected = $scope.php.versions[i];
                                return;
                            }
                        }
                    };

                    var processImpactedDomains = function(type, value, impactedDomains, selected) {
                        if (selected) {

                            // Currently there are only two types: domain (string value), system_default (bool value).
                            $scope.actions.fetchingImpactedDomains = true;
                            configService.fetchImpactedDomains(type, value)
                                .then(function(result) {
                                    var domains = result.data;
                                    if (result.status && domains.length > 0) {
                                        impactedDomains.show = impactedDomains.warn = true;
                                        impactedDomains.showMore = domains.length > 10;
                                        var displayText = ( type === "domain" ) ?
                                            LOCALE.maketext("A change to the “[output,strong,_1]” domain‘s PHP version affects the following domains:", value)
                                            :
                                            LOCALE.maketext("A change to the system default PHP version affects the following domains:");
                                        impactedDomains.text = displayText;
                                        impactedDomains.domains = _.sortBy(domains);
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "fetchImpactedDomainsError"
                                    });
                                    impactedDomains.show = impactedDomains.warn = false;
                                })
                                .finally(function() {
                                    $scope.actions.fetchingImpactedDomains = false;
                                    $scope.impactedDomains = impactedDomains;
                                });
                        } else {
                            impactedDomains.show = impactedDomains.warn = false;
                            $scope.impactedDomains = impactedDomains;
                        }
                    };

                    var formatFPMMemoryNeeded = function(fpmData) {
                        var memoryRequired = fpmData.environment.memory_needed * 1024;
                        return memoryRequired;
                    };

                    var checkFPMSystemStatus = function(fpmData) {
                        var systemStatus = PARSE.parsePerlBoolean(fpmData.status.default_accounts_to_fpm);
                        return systemStatus;
                    };

                    var checkFPMMemoryWarning = function(fpmData) {
                        var showMemoryWarning = PARSE.parsePerlBoolean(fpmData.environment.show_warning);

                        if (showMemoryWarning) {
                            $scope.fpm.requiredMemoryAmount = formatFPMMemoryNeeded(fpmData);
                        }

                        return showMemoryWarning;
                    };

                    var createFPMPackageCheckList = function(phpVersions) {
                        var fpmPackageChecklist = [];
                        phpVersions.forEach(function(version) {
                            if (version.version !== "inherit" && !altRegex.test(version.version)) {
                                fpmPackageChecklist.push(version.version);
                            }
                        });

                        // Add ea-apache24-mod_proxy_fcgi in addition to php versions
                        fpmPackageChecklist.push("ea-apache24-mod_proxy_fcgi");
                        return fpmPackageChecklist;
                    };

                    var isSystemPHPFPMInstalled = function(fpmPackages, phpSystemDefault) {
                        phpSystemDefault = phpSystemDefault + "-php-fpm";
                        for (var i = 0, len = fpmPackages.length; i < len; i++) {
                            if (phpSystemDefault === fpmPackages[i].package) {
                                return true;
                            }
                        }
                        return false;
                    };

                    var createMissingPackageDisplayVersions = function(fpmPackageChecklist) {
                        var displayVersions = "";

                        if (fpmPackageChecklist[0] === "ea-apache24-mod_proxy_fcgi") {
                            fpmPackageChecklist.shift();
                        }

                        fpmPackageChecklist.forEach(function(fpmPackage) {
                            if (fpmPackage !== "ea-apache24-mod_proxy_fcgi") {
                                fpmPackage = fpmPackage.split("ea-php");
                                fpmPackage = fpmPackage[1].split("-php-fpm");
                                fpmPackage = fpmPackage[0].split("").join(".");
                            }
                            displayVersions = displayVersions + fpmPackage + ", ";
                        });

                        return displayVersions;
                    };

                    var checkCompatibleVersions = function(fpmPackages, fpmPackageChecklist) {
                        var compatibleVersions = [];
                        var installedVersions = [];
                        var extendedPackageChecklist = [];
                        fpmPackageChecklist.forEach(function(fpmPackage) {
                            if (fpmPackage !== "ea-apache24-mod_proxy_fcgi") {
                                fpmPackage = fpmPackage + "-php-fpm";
                            }
                            extendedPackageChecklist.push(fpmPackage);
                        });
                        for (var i = 0, len = fpmPackages.length; i < len; i++) {
                            for (var j = 0, length = extendedPackageChecklist.length; j < length; j++) {
                                if (fpmPackages[i].package === extendedPackageChecklist[j]) {
                                    installedVersions.push(fpmPackages[i].package);

                                    if (fpmPackages[i].package !== "ea-apache24-mod_proxy_fcgi") {
                                        compatibleVersions.push(fpmPackages[i].package);
                                    }
                                    extendedPackageChecklist.splice(extendedPackageChecklist.indexOf(fpmPackages[i].package), 1);
                                }
                            }
                        }
                        $scope.fpm.missingPackagesDisplay = createMissingPackageDisplayVersions(extendedPackageChecklist);
                        $scope.php.installedVersion = createMissingPackageDisplayVersions(installedVersions).slice(0, $scope.php.installedVersion.length - 2);
                        $scope.php.compatibleVersions = compatibleVersions;
                        $scope.fpm.missingPackages = extendedPackageChecklist;
                    };

                    var createQueryLink = function(fpmPackageChecklist) {
                        var queryString =
                        _.join(
                            _.map(fpmPackageChecklist,
                                function(fpmPkg) {
                                    return "install=" + fpmPkg;
                                }
                            ), "&"
                        );
                        return PAGE.cp_security_token + "/scripts7/EasyApache4/review?" + queryString;
                    };

                    var isFcgiMissing = function(fpmMissingPackages) {
                        if ($scope.fpm.missingPackages.indexOf("ea-apache24-mod_proxy_fcgi") !== -1) {
                            return true;
                        } else {
                            return false;
                        }
                    };

                    var runFPMPackageCheck = function(fpmPackageData) {
                        $scope.fpm.packageChecklist = createFPMPackageCheckList($scope.php.versions);
                        $scope.php.systemDefault.hasFPMInstalled = isSystemPHPFPMInstalled(fpmPackageData, $scope.php.systemDefault.version);

                        // fpm.packageChecklist turns into fpm.missingPackages here
                        checkCompatibleVersions(fpmPackageData, $scope.fpm.packageChecklist);

                        if ($scope.fpm.missingPackages.length) {
                            $scope.fpm.ea4ReviewLink = createQueryLink($scope.fpm.missingPackages);
                        }
                        $scope.fpm.fcgiMissing = isFcgiMissing($scope.fpm.missingPackages);
                    };

                    var getFPMInfo = function() {
                        $scope.actions.loadingFPMInfo = true;
                        return configService.getPHPFPMInfo()
                            .then(function(data) {
                                $scope.fpm.completePackageData = data.packages;
                                $scope.fpm.systemStatus = checkFPMSystemStatus(data);
                                $scope.fpm.showMemoryWarning = checkFPMMemoryWarning(data);
                                runFPMPackageCheck(data.packages);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "fetchFPMInfoError"
                                });
                            })
                            .finally(function() {
                                $scope.actions.loadingFPMInfo = false;
                            });
                    };

                    var createPHPDisplayVersions = function(phpVersions) {
                        var versionObj;
                        var versions = [];
                        phpVersions.forEach(function(version) {
                            versionObj = {};
                            versionObj["version"] = version;
                            versionObj["displayVersion"] = configService.transformPhpFormat(version);
                            versions.push(versionObj);
                        });
                        return versions;
                    };

                    var labelInheritedAccounts = function(phpAccountList) {
                        phpAccountList.forEach(function(account) {
                            if ( typeof account.phpversion_source !== "undefined" ) {
                                var type = "", value = "";
                                if ( typeof account.phpversion_source.domain !== "undefined" ) {
                                    type = "domain";
                                    value = account.phpversion_source.domain;
                                } else if (typeof account.phpversion_source.system_default !== "undefined") {
                                    type = "system_default";
                                    value = LOCALE.maketext("System Default");
                                }

                                if ((type === "domain" && value !== account.vhost) ||
                            type === "system_default") {
                                    account.version = "inherit";
                                    account.displayVersion = "inherit (" + $scope.php.systemDefault.version + ")";
                                    account.inherited = true;
                                    account.inheritedInfo = LOCALE.maketext("This domain inherits its [asis,PHP] version “[output,em,_1]” from: [output,strong,_2]", account.display_php_version, value);
                                }
                            }
                        });
                        return phpAccountList;
                    };

                    var labelUnavailableAccounts = function(phpAccountList) {
                        var phpVersions = [];
                        $scope.php.versions.forEach(function(version) {
                            phpVersions.push(version.version);
                        });
                        phpAccountList.forEach(function(account) {
                            if (account.version === "inherit") {
                                account.isUnavailableVersion = false;
                            } else if (phpVersions.indexOf(account.version) === -1) {
                                account.isUnavailableVersion = true;
                                account.isUnavailableVersionMessage = LOCALE.maketext("The domain ‘[_1]’ uses a PHP version, ‘[_2]’, that no longer exists in the system. You must select a new PHP version for this domain.", account.vhost, account.version);
                            } else {
                                account.isUnavailableVersion = false;
                            }
                        });
                        return phpAccountList;
                    };

                    var createAccountTable = function(phpAccountList) {
                        phpAccountList = labelInheritedAccounts(phpAccountList);
                        phpAccountList = labelUnavailableAccounts(phpAccountList);
                        domainTable.load(phpAccountList);
                        domainTable.update();
                        $scope.meta = domainTable.getMetadata();
                        $scope.php.accountList = domainTable.getList();
                        $scope.php.paginationMessage = domainTable.paginationMessage();
                    };

                    var createPHPVersionListInherit = function(phpVersionList) {
                        var clonedList = phpVersionList.slice();
                        clonedList.push({
                            version: "inherit",
                            displayVersion: "inherit"
                        });
                        return clonedList;
                    };

                    var preSelectPerDomainValue = function() {
                        for (var i = 0, len = $scope.php.versionsInherit.length; i < len; i++) {
                            if ($scope.php.versionsInherit[i].version === $scope.php.systemDefault.version) {
                                $scope.php.perDomain.selected = $scope.php.versionsInherit[i];
                                return;
                            }
                        }
                    };

                    var setInitialPHPFPMData = function() {
                        if (PAGE.php_versions.data) {
                            $scope.actions.fpmConversionRunning = $scope.actions.fpmConversionRunningOnLoad = PARSE.parsePerlBoolean(PAGE.fpm_conversion_in_progress);
                            $scope.php.noVersions = false;
                        } else {
                            $scope.php.noPHPVersionsError = PAGE.php_versions.metadata.reason;
                            $scope.php.noVersions = true;
                        }
                        if ($scope.actions.fpmConversionRunning) {
                            monitorConversionStatus();
                        }
                    };

                    var getAccountList = function() {
                        $scope.actions.loadingAccountList = true;
                        clearTable();
                        return configService.fetchList()
                            .then(function(data) {
                                createAccountTable(data.items);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "fetchTableListError"
                                });
                            })
                            .finally(function() {
                                $scope.php.allRowsSelected = false;
                                $scope.actions.loadingAccountList = false;
                            });
                    };

                    var clearTable = function() {
                        domainTable.clear();
                        $scope.php.totalSelectedDomains = 0;
                    };

                    var clearPoolOptionsDisplaySettings = function() {
                        $rootScope.editPoolOptionsMode = false;
                        if (PAGE.poolOptionsDisplayMode) {
                            delete PAGE.poolOptionsDisplayMode;
                        }
                    };

                    var isPhpEol = function(phpVer) {
                        return _.includes($scope.php.eolPhps, phpVer);
                    };

                    $scope.php.eolWarningClass = function(type) {
                        var cssClass = "";
                        switch (type) {
                            case "systemDefault":
                                if ($scope.php.systemDefault.showEolMsg) {
                                    cssClass = "system eol-warning";
                                }
                                break;
                            default:
                                cssClass = "";
                        }
                        return cssClass;
                    };

                    $scope.php.toggleEolWarning = function(type, show) {
                        switch (type) {
                            case "systemDefault":
                                $scope.php.systemDefault.showEolMsg = show;
                                break;
                        }
                        if (show) {
                            $scope.php.eolWarningClass(type);
                        } else {
                            $scope.php.eolWarningClass();
                        }
                    };

                    var setPhpEolData = function() {
                        var eolPhps = [];
                        if ($scope.php.versions.length > 0) {
                            return configService.getEA4Recommendations()
                                .then(function(result) {
                                    if (result && typeof result.data !== "undefined") {
                                        var keys = _.filter(_.keys(result.data), function(key) {
                                            return (/^ea-php\d{2}$/.test(key));
                                        });

                                        // Extract only the keys for the installed PHPs.
                                        keys = _.sortBy(_.intersection(keys, _.map($scope.php.versions, "version")));
                                        _.each(keys, function(key) {
                                            _.each(result.data[key], function(reco) {
                                                if (_.includes(reco.filter, "eol")) {
                                                    eolPhps.push(key);
                                                }
                                            });
                                        });
                                        if (eolPhps.length > 0) {
                                            $scope.php.eolPhps = eolPhps;
                                            var displayEolPhps = _.map(eolPhps, function(php) {
                                                return configService.friendlyPhpFormat(php);
                                            });
                                            var eolWarningMsg = LOCALE.maketext("[output,strong,Warning]: The [asis,PHP] [numerate,_2,version,versions] [list_and,_1] [numerate,_2,has,have] reached [output,acronym,EOL,End Of Life].", displayEolPhps, eolPhps.length) + " " + eolWarningMsgLastPart;
                                            $scope.php.showEolMsg = true;
                                            $scope.php.eolWarningMsg = eolWarningMsg;
                                        }
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "recommendationsError"
                                    });
                                });
                        }
                    };

                    var init = function() {

                        // ===No API calls===
                        clearPoolOptionsDisplaySettings();
                        $scope.clData = PAGE.cl_data;
                        $scope.clBannerText = LOCALE.maketext("[output,strong,cPanel] provides the most recent stable versions of PHP. If you require legacy versions of PHP, such as PHP [list_and,_3], [asis,CloudLinux] provides hardened and secured [asis,PHP] versions that are patched against all known vulnerabilities. To learn more about [asis,CloudLinux] Advanced PHP Features, please read [output,url,_1,Hardened PHP versions on CloudLinux,target,_2].", "https://go.cpanel.net/cloudlinuxhardenedphp", "_blank", [4.4, 5.1, 5.2, 5.3]);
                        setInitialPHPFPMData();

                        // ===API calls===

                        var promises = {
                            info: getFPMInfo(),
                            versions: getPHPVersions(),
                            system: getSystemPHP()
                        };

                        $q.all(promises)
                            .then(function(data) {
                                setPhpEolData();
                                preSelectPerDomainValue();
                                return getAccountList();
                            })
                            .finally(function(data) {
                                $timeout(function() {

                                    // $scope.php.systemDefault.eolWarningMsg = systemEolWarningMsg;
                                    $scope.php.toggleEolWarning("systemDefault", isPhpEol($scope.php.systemDefault.version));
                                }, 0);
                                $scope.actions.initialDataLoading = false;
                            });
                    };
                    init();
                }
            ]);
        return controller;
    }
);
