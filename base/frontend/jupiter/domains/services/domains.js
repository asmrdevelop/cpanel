// Copyright 2022 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

/** @namespace cpanel.domains.services.domains */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/uapi-request",
        "cjt/io/api2-request",
        "cjt/io/uapi",
        "cjt/io/api2",
        "cjt/modules",
        "cjt/services/APICatcher",
    ],
    function(angular, _, LOCALE, UAPIRequest, API2Request) {

        "use strict";

        var app = angular.module("cpanel.domains.domains.service", [
            "cjt2.services.apicatcher",
        ]);
        app.value("PAGE", PAGE);

        app.value("DOMAIN_TYPE_CONSTANTS", {
            SUBDOMAIN: "subdomain",
            ADDON: "addon",
            ALIAS: "alias",
            MAIN: "main_domain",
        });

        var CAN_EDIT_DOCROOT = {
            documentRoot: true,
        };

        app.factory("domains", ["$q", "APICatcher", "DOMAIN_TYPE_CONSTANTS", "PAGE", function($q, APICatcher, DOMAIN_TYPE_CONSTANTS, PAGE) {

            /**
             * service wrapper for domain related functions
             *
             * @module domains
             *
             * @param  {Object} $q angular $q object
             * @param  {Object} APICatcher cjt2 APICatcher service
             * @param  {Object} DOMIAIN_TYPE_CONSTANTS constants objects for use on domain types
             * @param  {Object} PAGE window.PAGE object
             *
             * @example
             * $domainsService.get()
             *
             */

            var _flattenedDomains;
            var _mainDomain;
            var _domainLookupMap = {};
            var _parkDomains;
            var _addOnDomains;
            var _subDomains;
            var _usageStats;

            var Domain = function Domain(domainObject) {

                var self = this;

                Object.keys(domainObject).forEach(function(key) {
                    self[key] = domainObject[key];
                });

                self.protocol = self.isHttpsRedirecting ? "https" : "http";
                self.isWildcard = self["domain"] && self["domain"].substr(0, 1) === "*";
                self.canBeSuggested = !self.isWildcard;

            };

            var _domainTypes = [
                {
                    label: LOCALE.maketext("Subdomain"),
                    value: DOMAIN_TYPE_CONSTANTS.SUBDOMAIN,
                    requiresCustomDocumentRoot: true,
                    stat: "subdomains",
                },
                {
                    label: LOCALE.maketext("Addon"),
                    value: DOMAIN_TYPE_CONSTANTS.ADDON,
                    requiresCustomDocumentRoot: true,
                    dependantStat: "subdomains",
                    stat: "addon_domains",
                },
                { label: LOCALE.maketext("Alias"), value: DOMAIN_TYPE_CONSTANTS.ALIAS, stat: "aliases" },
            ];

            var Domains = function() {};

            Domains.prototype = APICatcher;

            // -------- UTILS -------------

            Domains.prototype._cacheDomain = function _cacheDomain(domainObject) {

                if (!_flattenedDomains) {
                    _flattenedDomains = [];
                }

                var domain = new Domain(domainObject);

                if (!_domainLookupMap[domain.domain]) {
                    _domainLookupMap[domain.domain] = domain;
                    _flattenedDomains.push(domain);
                }


                return domainObject;
            };

            Domains.prototype._uncacheDomain = function _uncacheDomain(domain) {
                var self = this;

                if (!_flattenedDomains) {
                    return false;
                }

                var domainObject = self._getDomainObject(domain);

                for (var i = _flattenedDomains.length - 1; i >= 0; i--) {
                    if (_flattenedDomains[i].domain === domainObject.domain) {
                        _flattenedDomains.splice(i, 1);
                    }
                }
            };

            Domains.prototype.getCurrentDomains = function getCurrentDomains() {
                return _flattenedDomains;
            };

            function _findStatById(_stats, id) {
                for (var statI in _stats) {
                    if (_stats.hasOwnProperty(statI) && _stats[statI].id === id) {
                        return _stats[statI];
                    }
                }
                return;
            }

            function _findDomainTypeByValue(value) {
                for (var domainTypeI in _domainTypes) {
                    if (_domainTypes.hasOwnProperty(domainTypeI) && _domainTypes[domainTypeI].value === value) {
                        return _domainTypes[domainTypeI];
                    }
                }
                return;
            }

            function _canCustomizeDocumentRoots() {
                return PAGE.hasWebServerRole === "1";
            }

            function _checkStatOverLimit(stat) {

                if (!stat) {
                    return;
                }

                var max = stat.maximum === null ? undefined : Number(stat.maximum);
                var usage = Number(stat.usage);

                if (!isNaN(max)) {

                    var per = usage / max;
                    if (max === 0 || per >= 1) {
                        return true;
                    }

                }

                return false;

            }

            Domains.prototype._getDomainObject = function _getDomainObject(domain) {
                var self = this;
                if (typeof domain === "string") {
                    return self.findDomainByName(domain);
                }

                return domain;
            };

            Domains.prototype._getSubDomainObject = function _getDomainObject(subdomain) {
                var self = this;
                if (typeof subdomain === "string") {
                    return self.findDomainByName(subdomain + "." + self.getMainDomain().domain);
                }

                return subdomain;
            };

            Domains.prototype._associateAddonDomains = function _associateAddonDomains() {
                var self = this;

                angular.forEach(_addOnDomains, function(addonDomain) {
                    var subdomainObject = self._getSubDomainObject(addonDomain.subdomain);
                    if (subdomainObject) {
                        subdomainObject.associatedAddonDomain = addonDomain.domain;
                    }
                });

            };

            // -------- \ UTILS -------------

            // -------- CREATE -------------

            /**
             * API Wrapper for adding a subdomain
             *
             * @method addSubdomain
             *
             * @param  {Object} domainObject object representing all the aspects of the domains
             *
             * @return {Promise<Object>} returns the api promise and then the newly added domain
             *
             */

            Domains.prototype.addSubdomain = function addSubdomain(domainObject) {
                var self = this;
                var apiCall = new API2Request.Class();
                apiCall.initialize("SubDomain", "addsubdomain");
                var subdomain = domainObject.subdomain.substr(0, domainObject.subdomain.length - (domainObject.domain.length + 1));
                apiCall.addArgument("domain", subdomain);
                apiCall.addArgument("rootdomain", domainObject.domain);
                apiCall.addArgument("canoff", "1");
                apiCall.addArgument("disallowdot", "0");
                apiCall.addArgument("dir", domainObject.fullDocumentRoot);

                return self.promise(apiCall).then(function(result) {
                    var domain = domainObject.newDomainName;
                    return self.fetchSingleDomainData(domain).then(function(updatedDomain) {
                        updatedDomain = angular.extend(updatedDomain, {
                            subdomain: updatedDomain.subdomain,
                            rootDomain: domainObject.domain,
                            type: DOMAIN_TYPE_CONSTANTS.SUBDOMAIN,
                            canEdit: PAGE.hasWebServerRole && CAN_EDIT_DOCROOT,
                            canRemove: true,
                        });
                        return self._cacheDomain(updatedDomain);
                    });
                });
            };

            /**
             * API Wrapper for adding an addon domain
             *
             * @method addAddonDomain
             *
             * @param  {Object} domainObject object representing all the aspects of the domains
             *
             * @return {Promise<Object>} returns the api promise and then the newly added domain
             *
             */

            Domains.prototype.addAddonDomain = function addAddonDomain(domainObject) {

                var self = this;

                var apiCall = new API2Request.Class();
                apiCall.initialize("AddonDomain", "addaddondomain");
                apiCall.addArgument("subdomain", domainObject.subdomain);
                apiCall.addArgument("newdomain", domainObject.newDomainName);
                apiCall.addArgument("ftp_is_optional", "1");
                apiCall.addArgument("dir", domainObject.documentRoot);

                return self.promise(apiCall).then(function() {
                    return self.fetchSingleDomainData(domainObject.newDomainName).then(function(updatedDomain) {
                        var addonDomain = angular.extend(angular.copy(updatedDomain), {
                            type: DOMAIN_TYPE_CONSTANTS.ADDON,
                            subdomain: domainObject.subdomain,
                            canEdit: PAGE.hasWebServerRole && CAN_EDIT_DOCROOT,
                            canRemove: true,
                        });
                        self._cacheDomain(angular.extend(angular.copy(updatedDomain), {
                            domain: domainObject.subdomain + "." + domainObject.domain,
                            subdomain: domainObject.subdomain,
                            type: DOMAIN_TYPE_CONSTANTS.SUBDOMAIN,
                            associatedAddonDomain: addonDomain,
                            canEdit: PAGE.hasWebServerRole && CAN_EDIT_DOCROOT,
                            canRemove: true,
                        }));
                        return self._cacheDomain(addonDomain);
                    });

                });
            };

            /**
             * API Wrapper for adding an alias domain
             *
             * @method addAliasDomain
             *
             * @param  {Object} domainObject object representing all the aspects of the domains
             *
             * @return {Promise<Object>} returns the api promise and then the newly added domain
             *
             */

            Domains.prototype.addAliasDomain = function addAliasDomain(domainObject) {

                var self = this;

                var apiCall = new API2Request.Class();
                apiCall.initialize("Park", "park");
                apiCall.addArgument("domain", domainObject.newDomainName);

                return self.promise(apiCall).then(function() {
                    var parkedDomain = angular.copy(self.getMainDomain());
                    parkedDomain.domain = domainObject.newDomainName;
                    parkedDomain.type = DOMAIN_TYPE_CONSTANTS.ALIAS;
                    parkedDomain.canRemove = true;
                    return self._cacheDomain(parkedDomain);
                });
            };

            /**
             * Add a domain, automatically selecting APIs based on which domainType is set
             *
             * @method add
             *
             * @param  {Object} domainObject object representing all the aspects of the domains
             *
             * @return {Promise<Object>} returns the api promise and then the newly added domain
             *
             */

            Domains.prototype.add = function _addNewDomain(domainObject) {

                var self = this;

                var addNewPromise;

                if (domainObject.domainType === DOMAIN_TYPE_CONSTANTS.SUBDOMAIN) {
                    addNewPromise = self.addSubdomain(domainObject);
                } else if (domainObject.domainType === DOMAIN_TYPE_CONSTANTS.ADDON ) {
                    addNewPromise = self.addAddonDomain(domainObject);
                } else if (domainObject.domainType === DOMAIN_TYPE_CONSTANTS.ALIAS ) {
                    addNewPromise = self.addAliasDomain(domainObject);
                }

                addNewPromise.then(function(result) {

                    var domainType = _findDomainTypeByValue(domainObject.domainType);
                    var stat = _findStatById(self.getUsageStats(), domainType.stat);
                    if (stat) {
                        stat.usage++;
                    }
                    self.updateDomainTypeLimits();
                    return result;

                });

                return addNewPromise;

            };

            // -------- \ CREATE -------------

            /**
             * Convert a relative document root to a full document root based on the homedir and the PAGE.requirePublicHTMLSubs
             *
             * @method generateFullDocumentRoot
             *
             * @param  {String} relativeDocumentRoot document root relative to the homedir
             *
             * @return {String} returns the parsed document root
             *
             */

            Domains.prototype.generateFullDocumentRoot = function generateFullDocumentRoot(relativeDocumentRoot) {
                var self = this;

                var requirePublicHTMLSubs = PAGE.requirePublicHTMLSubs.toString() === "1";
                var fullDocumentRoot = self.getMainDomain().homedir + "/";
                if (requirePublicHTMLSubs) {
                    fullDocumentRoot += "public_html/";
                }
                fullDocumentRoot += relativeDocumentRoot ? relativeDocumentRoot.replace(/^\//, "") : "";
                return fullDocumentRoot;
            };

            // -------- READ -------------

            /**
             * Get the currently stored main domain
             *
             * @method getMainDomain
             *
             * @return {Object} returns the current main domain object
             *
             */

            Domains.prototype.getMainDomain = function _getMainDomain() {
                return _mainDomain;
            };

            /**
             * Find a domain object by the domain name
             *
             * @method findDomainByName
             *
             * @param  {String} domainName domain name (bob.com)
             *
             * @return {Object} returns the domain object if found
             *
             */
            Domains.prototype.findDomainByName = function _findDomainByName(domainName) {
                return _domainLookupMap[domainName];
            };

            /**
             * API Wrapper to fetch the main domain based on PAGE.mainDomain
             *
             * @method fetchSingleDomainData
             *
             * @return {Promise<Object>} returns a promise, then the single domain object
             *
             */

            Domains.prototype.fetchSingleDomainData = function fetchSingleDomainData(domain) {

                var self = this;
                var apiCall = new UAPIRequest.Class();
                apiCall.initialize("DomainInfo", "single_domain_data");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("return_https_redirect_status", 1);

                return self.promise(apiCall).then(function(result) {
                    var typeTranslated = 0;
                    if (result.data.type === "addon_domain") {
                        typeTranslated = DOMAIN_TYPE_CONSTANTS.ADDON;
                    } else if ( result.data.type === "sub_domain" ) {
                        typeTranslated = DOMAIN_TYPE_CONSTANTS.SUBDOMAIN;
                    }
                    return self.formatSingleDomain(result.data, typeTranslated);
                });
            };


            /**
             * API Wrapper to fetch the domains and cache them
             *
             * @method fetchDomains
             *
             * @return {Promise<Object>} returns a promise, then the main domain object
             *
             */

            Domains.prototype.fetchDomains = function fetchDomains() {

                var self = this;

                var apiCall = new UAPIRequest.Class();
                apiCall.initialize("DomainInfo", "domains_data");
                apiCall.addArgument("return_https_redirect_status", 1);

                return self.promise(apiCall).then(function(result) {
                    var mainDomain = self.formatSingleDomain(result.data.main_domain);
                    mainDomain.type =  DOMAIN_TYPE_CONSTANTS.MAIN;
                    mainDomain.canRemove = false;
                    _mainDomain = mainDomain;
                    self._cacheDomain(_mainDomain);

                    // Cache (most of) the rest of the domains to speed this up
                    _subDomains = [];
                    var domains = result.data.sub_domains || [];
                    domains.forEach(function(rawDomain) {
                        var parsedDomain = self.formatSingleDomain(rawDomain, DOMAIN_TYPE_CONSTANTS.SUBDOMAIN);
                        this.push(parsedDomain);
                        self._cacheDomain(parsedDomain);
                    }, _subDomains);

                    _addOnDomains = [];
                    domains = result.data.addon_domains || [];
                    domains.forEach(function(rawDomain) {
                        var parsedDomain = self.formatSingleDomain(rawDomain, DOMAIN_TYPE_CONSTANTS.ADDON);
                        this.push(parsedDomain);
                        self._cacheDomain(parsedDomain);

                        // Also add in this thing's backing subdomain
                        var subdomainObj = _.assign( {}, parsedDomain );
                        subdomainObj.domain = subdomainObj.rootDomain;
                        subdomainObj.type   = DOMAIN_TYPE_CONSTANTS.SUBDOMAIN;
                        _subDomains.push(subdomainObj);
                        self._cacheDomain(subdomainObj);
                    }, _addOnDomains);

                    _parkDomains = [];
                    result.data.parked_domains.forEach(function(rawDomain) {
                        var parsedDomain    = self.formatSingleDomain(result.data.main_domain, DOMAIN_TYPE_CONSTANTS.ALIAS);
                        parsedDomain.domain = rawDomain;
                        this.push(parsedDomain);
                        self._cacheDomain(parsedDomain);
                    }, _parkDomains);

                    return _mainDomain;
                });
            };

            Domains.prototype.formatSingleDomain = function formatSingleDomain(rawDomain, typeOverride) {
                var self = this;
                var singleDomain = {
                    domain: rawDomain.domain,
                    homedir: rawDomain.homedir,
                    documentRoot: rawDomain.documentroot || rawDomain.dir,
                    rootDomain: rawDomain.servername,
                    isHttpsRedirecting: parseInt(rawDomain.is_https_redirecting),
                    hasValidHTTPSAliases: parseInt(rawDomain.all_aliases_valid),
                    nonHTTPS: !parseInt(rawDomain.can_https_redirect),
                    redirectsTo: rawDomain.status === "not redirected" ? null : rawDomain.status,
                    type: rawDomain.type,
                    realRootDomain: PAGE.mainDomain,
                };
                if (typeOverride) {
                    singleDomain.type         = typeOverride;
                    singleDomain.homedir      = self.getMainDomain().homedir;
                    var altRootDomain = self.getMainDomain().domain;

                    // Root domain is going to differ when the domain in this context is a subdomain of an addon | parked domain.
                    if (typeOverride === DOMAIN_TYPE_CONSTANTS.SUBDOMAIN) {

                        // The subdomain could be of an addon|parked domain. So it is prudent to consider the last part
                        // of the domain as the root domain instead of hard coding it to the primary domain.
                        var lastPartOfDomain = rawDomain.domain.match(/.*\.(.+\..+)$/);
                        altRootDomain = (lastPartOfDomain) ? lastPartOfDomain[1] : altRootDomain;
                    }
                    var altSubDomain = singleDomain.rootDomain ? singleDomain.rootDomain.substr(0, singleDomain.rootDomain.lastIndexOf("." + altRootDomain)) : null;

                    singleDomain.canRemove    = true;
                    if (typeOverride !== DOMAIN_TYPE_CONSTANTS.ALIAS) {
                        singleDomain.canEdit      = PAGE.hasWebServerRole && CAN_EDIT_DOCROOT;
                        singleDomain.subdomain    = altSubDomain;
                    }

                    if (typeOverride === DOMAIN_TYPE_CONSTANTS.SUBDOMAIN) {
                        singleDomain.rootDomain = altRootDomain;
                    } else if ( typeOverride === DOMAIN_TYPE_CONSTANTS.ALIAS ) {
                        singleDomain.rootDomain = PAGE.mainDomain;
                    }
                }
                return singleDomain;
            };


            /**
             * API Wrapper to fetch the all domains (main, addon, subdomain, alias) and cache them
             *
             * @method get
             *
             * @return {Promise<Object>} returns a promise, then the array of all domain objects
             *
             */

            var domainsLoadingQ;

            Domains.prototype.get = function getDomains() {

                var self = this;

                if (domainsLoadingQ) {
                    return domainsLoadingQ;
                }

                if (_flattenedDomains) {
                    return $q.resolve(_flattenedDomains);
                }

                _flattenedDomains = [];

                return domainsLoadingQ = self.fetchDomains().then(function() {
                    self._associateAddonDomains();
                    return _flattenedDomains;
                }).finally(function() {
                    domainsLoadingQ = null;
                });

            };


            /**
             * API Wrapper to get the resource usage statistics
             *
             * @method getResourceUsageStats
             *
             * @return {Promise<Array>} returns a promise and then the array of usages statistics
             *
             */

            Domains.prototype.getResourceUsageStats = function _getResourceUsageStats() {

                var self = this;
                var apiCall = new UAPIRequest.Class();
                apiCall.initialize("ResourceUsage", "get_usages");

                return self.promise(apiCall).then(function(result) {
                    return result.data;
                });

            };

            /**
             * Get the currently stored domain types
             *
             * @method getDomainTypes
             *
             * @return {Array} array of domain type objects
             *
             */
            Domains.prototype.getDomainTypes = function _getBaseDomainTypes() {
                return _domainTypes;
            };

            /**
             * Get the currently stored usage statistics
             *
             * @method getUsageStats
             *
             * @return {Array} returns an array of usage stat objects
             *
             */
            Domains.prototype.getUsageStats = function _getUsageStats() {
                return _usageStats;
            };

            /**
             * Uses the current getUsageStats() and updates the overLimit on the domainTypes
             *
             * @method updateDomainTypeLimits
             *
             * @return {Array} returns the updated array of domain type objects
             *
             */
            Domains.prototype.updateDomainTypeLimits = function _updateDomainTypeLimits() {
                var self = this;

                var stats = self.getUsageStats();

                self.getDomainTypes().forEach(function(domainType) {
                    var domainTypeStat = _findStatById(stats, domainType.stat);
                    domainType.overLimit = _checkStatOverLimit(domainTypeStat);
                    if (!_canCustomizeDocumentRoots() && domainType.requiresCustomDocumentRoot ) {
                        domainType.overLimit = true;
                    } else if (!domainType.overLimit && domainType.dependantStat) {
                        domainType.overLimit = domainType.overLimit || _checkStatOverLimit(_findStatById(stats, domainType.dependantStat));
                    }
                });

                return self.getDomainTypes();

            };


            /**
             * Get the domain types and update their overlimit by quering the usage stats APIs
             *
             * @method getTypes
             *
             * param jsdocparam maybe?
             *
             * @return {Promise<Array>} returns a promise and then an array of domain types with the updated overLimit values
             *
             */
            Domains.prototype.getTypes = function _getDomainTypes() {
                var self = this;

                if (self.getUsageStats()) {
                    return $q.resolve(self.getDomainTypes());
                }


                return self.getResourceUsageStats().then(function(stats) {

                    _usageStats = stats;

                    self.updateDomainTypeLimits();

                    return self.getDomainTypes();

                });
            };

            // -------- \ READ -------------

            // -------- UPDATE -------------


            /**
             * Update the document root for a subdomain
             *
             * @method updateDocumentRoot
             *
             * @param  {String|Object} domain domain name or domain object
             *
             * @return {Promise<Object>} returns promise and then the updated domainObject
             *
             */
            Domains.prototype.updateDocumentRoot = function updateDocumentRoot(domain, documentRoot) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                ["subdomain", "rootDomain"].forEach(function(key) {
                    if (!domainObject[key]) {
                        throw new Error(key + " is required but undefined on " + domainObject.domain);
                    }
                });

                var rdomain = domainObject.rootDomain;
                if (domainObject.type === DOMAIN_TYPE_CONSTANTS.ADDON) {
                    rdomain = domainObject.realRootDomain;
                }

                var apiCall = new API2Request.Class();
                apiCall.initialize("SubDomain", "changedocroot");
                apiCall.addArgument("subdomain", domainObject.subdomain);
                apiCall.addArgument("rootdomain", rdomain);
                apiCall.addArgument("dir", documentRoot);

                return self.promise(apiCall).then(function(result) {
                    domainObject.documentRoot = documentRoot;

                    return self.fetchSingleDomainData(domainObject.domain).then(function(updatedDomain) {
                        var updatedDocumentRoot = updatedDomain.documentRoot;

                        // find and update existing domain
                        if (domainObject.type === DOMAIN_TYPE_CONSTANTS.ADDON) {

                            // This is an addon domain. So there is a subdomain that just had it's document root updated too
                            var subdomainObject = self._getSubDomainObject(domainObject.subdomain );
                            if (subdomainObject) {
                                subdomainObject.documentRoot = updatedDocumentRoot;
                            }
                        } else if (domainObject.associatedAddonDomain) {

                            // This is an addon domain. Check for an associated addon domain
                            var addonDomainObject = self._getDomainObject(domainObject.associatedAddonDomain);
                            addonDomainObject.documentRoot = updatedDocumentRoot;
                        }

                        domainObject.documentRoot = updatedDocumentRoot;

                        return domainObject;
                    });

                });
            };

            // -------- \ UPDATE -------------

            // -------- DELETE -------------

            /**
             * API Wrapper call to remove a subdomain
             *
             * @method removeSubdomain
             *
             * @param  {String|Object} domain domain name or domain object
             *
             * @return {Promise} returns the promise that removes the subdomain
             *
             */
            Domains.prototype.removeSubdomain = function removeSubdomain(domain) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                // If the domain does not contain its own rootDomain, it
                // is an indicator that the subdomain is parked on addon domain
                // which means the servername could not be used to extract the
                // subdomain. In this case we will use full domain as the removal point
                // for the api call (CPANEL-32624)
                var rootDomainRE = new RegExp("." + domainObject.rootDomain + "$");
                var domainStr;
                if (domainObject.domain.match(rootDomainRE)) {
                    domainStr = domainObject.subdomain + "_" + domainObject.rootDomain;
                } else {
                    domainStr = domainObject.domain;
                }

                var apiCall = new API2Request.Class();
                apiCall.initialize("SubDomain", "delsubdomain");
                apiCall.addArgument("domain", domainStr);

                return self.promise(apiCall);
            };

            /**
             * API Wrapper call to remove an addon domain
             *
             * @method removeAddonDomain
             *
             * @param  {String|Object} domain domain name or domain object
             *
             * @return {Promise} returns the promise that removes the addon domain
             *
             */
            Domains.prototype.removeAddonDomain = function removeAddonDomain(domain) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                var apiCall = new API2Request.Class();
                apiCall.initialize("AddonDomain", "deladdondomain");
                apiCall.addArgument("domain", domainObject.domain);

                // The addon domain's subdomain, an underscore (_), and the addon domain's main domain.
                apiCall.addArgument("subdomain", domainObject.subdomain + "_" + self.getMainDomain().domain);

                return self.promise(apiCall);
            };

            /**
             * API Wrapper call to remove an alias domain
             *
             * @method removeAliasDomain
             *
             * @param  {String|Object} domain domain name or domain object
             *
             * @return {Promise} returns the promise that removes the alias domain
             *
             */
            Domains.prototype.removeAliasDomain = function removeAliasDomain(domain) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                var apiCall = new API2Request.Class();
                apiCall.initialize("Park", "unpark");
                apiCall.addArgument("domain", domainObject.domain);

                return self.promise(apiCall);
            };

            /**
             * API Wrapper call to remove a redirect for a domain
             *
             * @method removeRedirect
             *
             * @param  {String|Object} domain domain name or domain object
             *
             * @return {Promise} returns the promise that removes the redirect from the domain
             *
             */
            Domains.prototype.removeRedirect = function removeRedirect(domain) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                var apiCall = new UAPIRequest.Class();
                apiCall.initialize("Mime", "delete_redirect");
                apiCall.addArgument("domain", domainObject.domain);
                apiCall.addArgument("src", domainObject.redirectTo);
                apiCall.addArgument("redirect", domainObject.documentRoot);

                return self.promise(apiCall).then(function() {
                    domainObject.redirectTo = "";
                });
            };


            Domains.prototype._removeDomainAdjustStats = function _removeDomainAdjustStats(domain) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                if (!domainObject) {
                    return;
                }

                // Remove the subdomain too, it's automatically deleted by the API
                if (domainObject.type === DOMAIN_TYPE_CONSTANTS.ADDON) {
                    self._removeDomainAdjustStats(domainObject.subdomain + "." + self.getMainDomain().domain);
                }

                self._uncacheDomain(domainObject);

                // Update Stat for Domain Type
                var domainTypeObject = _findDomainTypeByValue(domainObject.type);
                var stat = _findStatById(self.getUsageStats(), domainTypeObject.stat);
                if (stat) {
                    stat.usage--;
                }
                self.updateDomainTypeLimits();
            };

            /**
             * Remove a domain, redirects, and adjust statistics for the domain type
             *
             * @method remove
             *
             * @param  {String|Object} domain domain name or domain object
             *
             * @return {Promise} returns the promise that will remove the domain and redirects for a domain
             *
             */
            Domains.prototype.remove = function removeDomain(domain) {
                var self = this;
                var domainObject = self._getDomainObject(domain);

                var originalCanEdit = domainObject.canEdit;
                domainObject.canEdit = false;

                var errorsEncounterd = false;

                var promises = [];

                if ( domainObject.type === DOMAIN_TYPE_CONSTANTS.SUBDOMAIN ) {
                    promises.push(self.removeSubdomain(domainObject));
                } else if ( domainObject.type === DOMAIN_TYPE_CONSTANTS.ADDON ) {
                    promises.push(self.removeAddonDomain(domainObject));
                } else if ( domainObject.type === DOMAIN_TYPE_CONSTANTS.ALIAS ) {
                    if (domainObject.redirectTo) {
                        promises.push(self.removeRedirect(domainObject));
                    }
                    promises.push(self.removeAliasDomain(domainObject));
                }

                domainObject.removing = true;

                return $q.all(promises).then(function(result) {
                    self._removeDomainAdjustStats(domainObject);
                }, function(result) {

                    if ( _.isArray(result) ) {
                        result.forEach(function(resultItem) {
                            if (resultItem && resultItem.error) {
                                errorsEncounterd = true;
                                throw resultItem.error;
                            }
                        });
                    } else if (result && result.error) {
                        errorsEncounterd = true;
                        throw result.error;
                    }

                    // failed, restore edit capability
                    domainObject.canEdit = originalCanEdit;
                }).finally(function() {
                    domainObject.removing = false;
                    if (!errorsEncounterd) {
                        self._uncacheDomain(domainObject);
                    }
                });
            };

            Domains.prototype.getDocumentRootPattern = function() {
                var regExp = new RegExp("^[^" + _.escapeRegExp('%?* :|"<>\\') + "]+$");
                return regExp;
            };

            // -------- \ DELETE -------------

            Domains.prototype.canRedirectHTTPS = function() {
                return PAGE.canRedirectHTTPS === "1";
            };

            /**
             * API Wrapper call to toggle secure redirect for domains
             *
             * @method toggleHTTPSRedirect
             *
             * @param  {Boolean} state turning the redirect On of Off as a boolean value
             *
             * @param  {String} singleDomain a single domain name to be toggled, optional
             *
             * @return {Promise} returns the promise that toggles secure redirect for the domains
             *
             */
            Domains.prototype.toggleHTTPSRedirect = function toggleHTTPSRedirect(state, singleDomain) {
                var self = this;

                var apiCall = new UAPIRequest.Class();
                apiCall.initialize("SSL", "toggle_ssl_redirect_for_domains");
                apiCall.addArgument("state", state ? 1 : 0);


                if (singleDomain) {
                    var domArg = singleDomain;
                    apiCall.addArgument("domains", domArg);
                } else {
                    var domains2Toggle = [];
                    for (var i = 0; i < _flattenedDomains.length; i++) {
                        if (_flattenedDomains[i].selected && !_flattenedDomains[i].associatedAddonDomain) {

                            // Add in non-assoc subs only to prevent passing dupes
                            if (typeof ( _flattenedDomains[i].associatedAddonDomain) === "undefined") {
                                domains2Toggle.push( _flattenedDomains[i].domain );
                            }
                        }
                    }

                    var domainList = domains2Toggle.join(",");

                    apiCall.addArgument("domains", domainList );
                }

                return self.promise(apiCall);
            };

            return new Domains();
        }]);
    }
);
