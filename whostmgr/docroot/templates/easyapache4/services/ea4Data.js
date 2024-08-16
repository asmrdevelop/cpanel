/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/ea4Data.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService",

        // App components
        "app/services/ea4Util",
    ],
    function(angular, _, API, APIREQUEST) {
        "use strict";

        var app = angular.module("whm.easyapache4.ea4Data", []);

        app.factory("ea4Data", ["$q", "$location", "ea4Util", "APIService", function($q, $location, ea4Util, APIService) {
            var oData = {
                isReadyForProvision: false,
                mpmRegex: /ea-apache24-mod[_-]mpm.*/i,
                modulesRegex: /ea-apache24-mod.*/i,
                phpRegex: /^ea-php\d{2}$/i,
                phpExtRegex: /ea-php\d{2}-.*/i,
                rubyRegex: /ea-ruby\d{2}-.*/i,
            };

            /**
             * Sets or gets the provision value
             *
             * @method provisionReady
             * @param {Boolean} value
             * @return {Boolean}
             */
            oData.provisionReady = function(value) {
                if (typeof value === "boolean") {
                    oData.isReadyForProvision = value;
                } else {
                    return oData.isReadyForProvision;
                }
            };

            /**
             * @method getProfiles
             * @return {Promise}
             */
            oData.getProfiles = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "ea4_list_profiles");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            // Keep the promise

                            // CJT2 whm-v1.js has parsedResponse wrapper
                            // which is returning wrong data when only 1 key exists
                            // in this response's data.
                            // i.e. when only 'cpanel' key exists in the response,
                            // whm-v1.js -> _reduce_list_data is removing it and returning
                            // and returning data differently.
                            // That is reason 'response.raw.data' is being used here
                            // to have a consistent return always.
                            // the above whm-v1.js method needs to be fixed.
                            deferred.resolve(response.raw.data);
                        } else {

                            // Pass the error along
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * @method getVhostsByPhpVersion
             * @param {String} - php version
             * @return {Promise}
             */
            oData.getVhostsByPhpVersion = function(version) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "php_get_vhosts_by_version");
                apiCall.addArgument("version", version);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            // Keep the promise
                            deferred.resolve(response.data);
                        } else {

                            // Pass the error along
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * TODO: this method needs to handle API failure
             *
             * @method ea4GetCurrentPkgList
             * @return {Promise}
             */
            oData.ea4GetCurrentPkgList = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();

                apiCall.initialize("", "ea4_get_currently_installed_packages");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * Returns ea4 meta info from the ea4_metainfo.json
             * It currently contains information about additional pacakges,
             * default PHP handler & default PHP package used.
             *
             * @method getEA4MetaInfo
             * @return {Promise}
             */
            oData.getEA4MetaInfo = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();

                apiCall.initialize("", "ea4_metainfo");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * Returns pkgInfoList for additional pacakges.
             *
             * @method getPkgInfoForAdditionalPackages
             * @argument {Object} pkgInfoList
             * @return {Object}
             */
            oData.getPkgInfoForAdditionalPackages = function(pkgInfoList) {
                var list = {};

                _.each(ea4Util.additionalPkgList, function(pkg) {
                    var pkgInfo = pkgInfoList[pkg];
                    if (typeof pkgInfo !== "undefined") {
                        list[pkg] = pkgInfo;
                    }
                });
                return list;
            };

            /**
             * Returns pkgInfoList filtered by type.
             *
             * @method getPkgInfoSubset
             * @argument {String} type
             * @argument {Object} pkgInfoList
             * @return {Object}
             */
            oData.getPkgInfoSubset = function(type, pkgInfoList) {
                var regex;
                if (type === "additional") {
                    return oData.getPkgInfoForAdditionalPackages(pkgInfoList);
                }

                switch (type) {
                    case "mpm":
                        regex = oData.mpmRegex;
                        break;
                    case "modules":
                        regex = oData.modulesRegex;
                        break;
                    case "php":
                        regex = oData.phpRegex;
                        break;
                    case "extensions":
                        regex = oData.phpExtRegex;
                        break;
                    case "ruby":
                        regex = oData.rubyRegex;
                        break;
                }
                return oData.filterByRegex(regex, pkgInfoList);
            };

            /**
             * @method filterByRegex
             * @argument {Regex} regex
             * @argument {Object} pkgInfoList
             * @return {Promise}
             */
            oData.filterByRegex = function(regex, pkgInfoList) {
                var list = {};
                if (typeof regex === "undefined") {
                    return pkgInfoList;
                }

                var filterPkgs =
                    _.filter(_.keys(pkgInfoList), function(pkg) {
                        return regex.test(pkg);
                    });
                filterPkgs.sort();
                _.each(filterPkgs, function(pkg) {
                    list[pkg] = pkgInfoList[pkg];
                });
                return list;
            };

            /**
             * @method resolvePackages
             * @argument {Array} packages - Array of string names
             * @return {Promise}
             */
            oData.resolvePackages = function(packages) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_resolve_actions");
                apiCall.addArgument("ns", "ea");
                _.each(packages, function(pkg, index) {
                    apiCall.addArgument("package-" + index, pkg );
                });

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.raw.data);
                        } else {
                            deferred.reject(response.raw.metadata.reason);
                        }
                    });

                return deferred.promise;
            };

            /**
             * @method doProvision
             * @argument {Array} installPackages - Array of string names
             * @argument {Array} uninstallPackages - Array of string names
             * @argument {Array} upgradePackages - Array of string names
             * @argument {String} profileID
             * @return {Promise}
             */
            oData.doProvision = function(installPackages, uninstallPackages, upgradePackages, profileID) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "package_manager_submit_actions");

                // apiCall.addArgument("profileID", profileID);

                // Prepare the package list
                _.each(installPackages, function(pkg, index) {
                    apiCall.addArgument("install-" + index, pkg );
                });
                _.each(uninstallPackages, function(pkg, index) {
                    apiCall.addArgument("uninstall-" + index, pkg );
                });
                _.each(upgradePackages, function(pkg, index) {
                    apiCall.addArgument("upgrade-" + index, pkg );
                });
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.data);
                    });

                return deferred.promise;
            };

            /**
             * @method tailingLog
             * @argument {Number} buildID
             * @argument {Number} offset
             * @return {Promise}
             */
            oData.tailingLog = function(buildID, offset) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_get_build_log");

                // Send the pid
                apiCall.addArgument("build", buildID);
                apiCall.addArgument("offset", offset);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.data);
                    });

                return deferred.promise;
            };

            /**
             * @method getPkgInfoList
             * @return {Promise}
             */
            oData.getPkgInfoList = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_get_package_info");
                apiCall.addArgument("ns", "ea");
                apiCall.addArgument("disable-excludes", "1");

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
             * @method cancelOperation
             */
            oData.cancelOperation = function() {
                oData.clearEA4LocalStorageItems();
                $location.path("profile");
            };

            /**
             * @method clearEA4LocalStorageItems
             */
            oData.clearEA4LocalStorageItems = function() {
                localStorage.removeItem("pkgInfoList");
                localStorage.removeItem("selectedProfile");
                localStorage.removeItem("selectedPkgs");
                localStorage.removeItem("provisionActions");
                localStorage.removeItem("customize");
                localStorage.removeItem("ea4Recommendations");
                localStorage.removeItem("ea4RawPkgList");
                localStorage.removeItem("ea4Update");

                ea4Util.hideFooter();
            };

            /**
             * Saves data in Local Storage
             *
             * @method setData
             * @argument {Object} dataItems
             */
            oData.setData = function(dataItems) {
                _.each(_.keys(dataItems), function(item) {
                    var stringifyItem = JSON.stringify(dataItems[item]);
                    localStorage.setItem(item, stringifyItem);
                });
            };

            /**
             * Gets data from Local Storage
             *
             * @method getData
             * @argument {String} item
             */
            oData.getData = function(item) {
                return JSON.parse(localStorage.getItem(item));
            };

            /**
             * Adds new properties to the packages object
             *
             * @method initPkgUIProps
             * @argument {Object} pkgData
             * @return {Object}
             */
            oData.initPkgUIProps = function(pkgData) {
                pkgData["actions"] = ea4Util.pkgActions;
                pkgData["recommendations"] = [];
                pkgData["multiRequirements"] = ea4Util.multiRequirements;
                pkgData["vhostWarning"] = ea4Util.vhostWarning;
                pkgData["mpmMissing"] = false;
                pkgData["mpmMissingMsg"] = "";
                pkgData["autoSelectExt"] = [];

                // TODO:: Add more as you come across. It's easy to know and track all the properties
                // if they are initialized at one place.
                return pkgData;
            };

            // move to ea4Util
            var setPkgSelections = function(selPkgs, pkgInfoList) {
                var allSelectedPkgs = ea4Util.gatherAllRequirementsOfPkgs(selPkgs, pkgInfoList);

                // Select all packages that are installed.
                _.each(allSelectedPkgs, function(pkg) {
                    if (typeof pkgInfoList[pkg] !== "undefined") {
                        pkgInfoList[pkg].selectedPackage = true;
                    }
                });
                return pkgInfoList;
            };

            /**
             * @method buildPkgInfoList
             * @argument {Array} selPkgs - Array of Strings
             * @argument {Array} packagesInfo - Array of Objects
             * @argument {Object} ea4Recommendations - The key is the pkg name, the value an Array of recommendations
             * @return {Object}
             */
            oData.buildPkgInfoList = function(selPkgs, packagesInfo, ea4Recommendations) {

                // Set all packages info.
                var pkgInfoList = {};

                // Ignore any debug packages
                packagesInfo = _.filter(packagesInfo, function(pkg) {
                    return (!/.*\-debuginfo/.test(pkg.package));
                });

                _.each(packagesInfo, function(pkg) {
                    var pkgName = pkg.package;

                    // Start adding UI specific attributes to each package data.
                    pkg = oData.initPkgUIProps(pkg);
                    if (!_.isEmpty(ea4Recommendations[pkgName])) {
                        pkg.recommendations = ea4Recommendations[pkgName];
                    }
                    pkg.selectedPackage = false;
                    pkg.displayName = ea4Util.getFormattedPackageName(pkgName);
                    pkgInfoList[pkgName] = pkg;
                });

                pkgInfoList = setPkgSelections(selPkgs, pkgInfoList);
                return pkgInfoList;
            };

            /**
             * @method fixYumCache
             * @return {Promise}
             */
            oData.fixYumCache = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();
                apiCall.addArgument("ns", "ea");
                apiCall.initialize("", "package_manager_fixcache");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * @method saveAsNewProfile
             * @argument {Object} content
             * @argument {String} filename
             * @argument {Number} overwrite
             * @return {Promise}
             */
            oData.saveAsNewProfile = function(content, filename, overwrite) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "ea4_save_profile");
                apiCall.addArgument("filename", filename);
                apiCall.addArgument("name", content.name);
                apiCall.addArgument("overwrite", overwrite);
                apiCall.addArgument("desc", content.desc || "");
                apiCall.addArgument("version", content.version || "");
                _.each(content.pkgs, function(pkg, index) {
                    apiCall.addArgument("pkg-" + index, pkg );
                });

                _.each(content.tags, function(tag, index) {
                    apiCall.addArgument("tag-" + index, tag );
                });

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response);
                        }
                    });
                return deferred.promise;
            };

            /**
             * @method getEA4Recommendations
             * @return {Promise}
             */
            oData.getEA4Recommendations = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();
                apiCall.initialize("", "ea4_recommendations");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * @method getUploadContentFromUrl
             * @argument {Object} uploadUrl
             * @return {Promise}
             */
            oData.getUploadContentFromUrl = function(uploadUrl) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cors_proxy_get");
                apiCall.addArgument("url", uploadUrl);

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
             * @method dataIsAvailable
             * @return {Boolean}
             */
            oData.dataIsAvailable = function() {
                if (oData.getData("pkgInfoList")) {
                    return true;
                } else {
                    return false;
                }
            };

            /**
             * @method getPkgInfoByType
             * @argument {String} type
             * @argument {Object} pkgInfoList
             * @return {Object}
             */
            oData.getPkgInfoByType = function(type, pkgInfoList) {
                var subsetPkgInfoList = [];
                if (type) {
                    subsetPkgInfoList = oData.getPkgInfoSubset(type, pkgInfoList);
                }
                return subsetPkgInfoList;
            };

            // Expose only required methods.
            return {
                provisionReady: oData.provisionReady,
                getProfiles: oData.getProfiles,
                ea4GetCurrentPkgList: oData.ea4GetCurrentPkgList,
                cancelOperation: oData.cancelOperation,
                getPkgInfoForAdditionalPackages: oData.getPkgInfoForAdditionalPackages,
                getPkgInfoSubset: oData.getPkgInfoSubset,
                filterByRegex: oData.filterByRegex,
                clearEA4LocalStorageItems: oData.clearEA4LocalStorageItems,
                resolvePackages: oData.resolvePackages,
                doProvision: oData.doProvision,
                tailingLog: oData.tailingLog,
                getPkgInfoList: oData.getPkgInfoList,
                setData: oData.setData,
                getData: oData.getData,
                initPkgUIProps: oData.initPkgUIProps,
                buildPkgInfoList: oData.buildPkgInfoList,
                getVhostsByPhpVersion: oData.getVhostsByPhpVersion,
                fixYumCache: oData.fixYumCache,
                saveAsNewProfile: oData.saveAsNewProfile,
                getEA4Recommendations: oData.getEA4Recommendations,
                getUploadContentFromUrl: oData.getUploadContentFromUrl,
                dataIsAvailable: oData.dataIsAvailable,
                getPkgInfoByType: oData.getPkgInfoByType,
                getEA4MetaInfo: oData.getEA4MetaInfo,
            };
        }]);
    }
);
