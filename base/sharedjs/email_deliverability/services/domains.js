/*
 * email_deliverability/services/domains.js           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define, PAGE */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "shared/js/email_deliverability/services/domainFactory",
        "shared/js/email_deliverability/services/DKIMRecordProcessor",
        "shared/js/email_deliverability/services/SPFRecordProcessor",
        "shared/js/email_deliverability/services/PTRRecordProcessor",
        "cjt/modules",
        "cjt/services/alertService",
        "cjt/modules",
        "cjt/services/APICatcher"
    ],
    function(angular, _, LOCALE, domainFactory, DKIMRecordProcessor, SPFRecordProcessor, PTRRecordProcessor) {

        "use strict";

        var MODULE_NAMESPACE = "shared.emailDeliverability.services.domains";
        var SERVICE_NAME = "DomainsService";
        var MODULE_REQUIREMENTS = [ "cjt2.services.apicatcher", "cjt2.services.alert" ];
        var SERVICE_INJECTABLES = ["$q", "$log", "$interval", "alertService", "APIInitializer", "APICatcher", "DOMAIN_TYPE_CONSTANTS", "PAGE"];

        // UAPI’s EmailAuth::validate_current_dkims returns the DKIM
        // record name as “domain”. This function intends to strip
        // the subdomain from that name to arrive at the domain name
        // for which the record exists. For example,
        // “newyork._domainkey.bob.com” becomes just “bob.com”.
        function _STRIP_DKIM_SUBDOMAIN(d) {
            return d.replace(/^.+\._domainkey\./, "");
        }

        var Zone = function(zoneName) {
            this.zone = zoneName;
            this.domains = [];
            this.lockDomain = null;
        };

        Zone.prototype.addDomain = function addDomainToZone(domain) {
            this.domains.push(domain);
        };

        // Returns a Domain object or null.
        Zone.prototype.getLockDomain = function getLockDomain() {
            return this.lockDomain;
        };

        // Requires a Domain object.
        Zone.prototype.lock = function lockZone(domainObj) {
            if (typeof domainObj !== "object") {
                throw new Error("Give a domain object!");
            }

            if (this.lockDomain) {
                throw new Error("Zone " + this.zone + " cannot lock for " + domainObj.domain + " because the zone is already locked for " + this.lockDomain + "!");
            }

            this.lockDomain = domainObj;
        };

        Zone.prototype.unlock = function unlockZone() {
            this.lockDomain = null;
        };


        /**
         *
         * Service Factory to generate the Domains service
         *
         * @module DomainsService
         * @memberof cpanel.emailDeliverability
         *
         * @param {ng.$q} $q
         * @param {ng.$log} $log
         * @param {Object} APICatcher base service
         * @param {Object} DOMAIN_TYPE_CONSTANTS constants lookup of domain types
         * @param {Object} PAGE window PAGE object created in template
         * @returns {Domains} instance of the Domains service
         */
        var SERVICE_FACTORY = function($q, $log, $interval, $alertService, $apiInit, APICatcher, DOMAIN_TYPE_CONSTANTS, PAGE) {

            var _flattenedDomains;
            var _domainLookupMap = {};
            var _domainZoneMap = {};
            var _zones = [];

            var Domains = function() {};

            Domains.prototype = Object.create(APICatcher);

            /**
             *
             * Cache domains for ease of later lookup
             *
             * @private
             *
             * @param {Domain} domain to cache for later lookup
             * @returns {Domain} stored domain
             */
            Domains.prototype._cacheDomain = function _cacheDomain(domain) {

                if (!_flattenedDomains) {
                    _flattenedDomains = [];
                }

                _domainLookupMap[domain.domain] = domain;

                // Cache DKIM Key Domain too
                _domainLookupMap["default._domainkey." + domain.domain] = domain;

                // Store Domain in flattened domains
                _flattenedDomains.push(domain);

                return domain;
            };

            /**
             *
             * Remove a domain from the cache lookup
             *
             * @private
             *
             * @param {Domain} domain to remove from cache
             * @returns {Boolean} success of domain removal
             */
            Domains.prototype._uncacheDomain = function _uncacheDomain(domain) {
                var self = this;

                if (!_flattenedDomains) {
                    return false;
                }

                var domainObject = self._getDomainObject(domain);

                for (var i = _flattenedDomains.length - 1; i >= 0; i--) {
                    if (_flattenedDomains[i].domain === domainObject.domain) {
                        _flattenedDomains.splice(i, 1);
                        return true;
                    }
                }

                return false;
            };

            /**
             *
             * Return a domain object. This is used to ensure you're always working with a Domain()
             * even when a string might have been passed to a function.
             *
             * @public
             *
             * @param {string|Domain} wantedDomain - domain name or domain object
             * @returns {Domain} matching wantedDomain
             */
            Domains.prototype._getDomainObject = function _getDomainObject(wantedDomain) {

                var self = this;

                var domain = wantedDomain;

                if (typeof domain === "string") {
                    domain = self.findDomainByName(domain);
                }

                if (domain instanceof domainFactory.getClass() !== true) {
                    $log.warn("Could not find domain “" + wantedDomain + "”");
                }

                return domain;
            };

            /**
             *
             * Find a domain using the domain name string
             *
             * @public
             *
             * @param {string} domainName - domain name to find
             * @returns {Domain} matching domainName
             */
            Domains.prototype.findDomainByName = function _findDomainByName(domainName) {
                return _domainLookupMap[domainName];
            };

            /**
             *
             * Returns all currently loaded and stored domains
             *
             * @public
             *
             * @returns Array<Domain> returns a list of all loaded domains
             */
            Domains.prototype.getAll = function getAllDomains() {
                return _flattenedDomains;
            };

            /**
             *
             * API Wrapper to fetch the all domains (main, addon, subdomain, alias) and cache them
             *
             * @public
             *
             * @returns Promise<Array<Domain>>
             */
            Domains.prototype.fetchAll = function fetchAllDomains() {
                var self = this;

                if (self.getAll()) {
                    return $q.resolve(self.getAll());
                }

                _flattenedDomains = [];

                var domains = PAGE.domains || [];

                domains.forEach(function(domain) {
                    if (domain.substring(0, 2) === "*.") {
                        return;
                    }
                    var domainObj = domainFactory.create({
                        domain: domain,
                        type: domain === PAGE.mainDomain ? DOMAIN_TYPE_CONSTANTS.MAIN : DOMAIN_TYPE_CONSTANTS.DOMAIN
                    });
                    self._cacheDomain(domainObj);
                });

                return $q.resolve(self.getAll());

            };

            /**
             *
             * Extract Mail IPS from a validate_current_ptrs API Result
             *
             * @private
             *
             * @param {Object} results object from API with .data array
             */
            Domains.prototype._extractMailIPs = function _extractMailIPs(results) {
                var data = results.data;

                data.forEach(function(ptrResult) {
                    var domain = this._getDomainObject(ptrResult.domain);
                    if (domain) {
                        domain.setMailIP(ptrResult.ip_version, ptrResult.ip_address);
                    }
                }, this);

            };

            /**
             * Find a domain zone by the domain name
             *
             * @param {String} zoneName name of the zone to find
             * @returns {Zone}
             */
            Domains.prototype.findZoneByName = function findZoneByName(zoneName) {
                for (var i = 0; i < _zones.length; i++) {
                    if (_zones[i].zone === zoneName) {
                        return _zones[i];
                    }
                }

                return null;
            };

            /**
             * Find domain zone by domain or domain name
             *
             * @param {Domain|String} domain
             * @returns {Zone}
             */
            Domains.prototype.findZoneByDomain = function findZoneByDomain(domain) {
                var domainObj = this._getDomainObject(domain);
                return _domainLookupMap[domainObj.domain];
            };


            /**
             * Add a domain to an existing zone, or create it
             *
             * @private
             *
             * @param {Domain} domain
             * @param {String} zone
             */
            Domains.prototype._addDomainToZone = function _addDomainToZone(domain, zone) {
                var zoneObj = this.findZoneByName(zone);
                if (!zoneObj) {
                    zoneObj = new Zone(zone);
                    _zones.push(zoneObj);
                }
                domain.zone = zone;
                zoneObj.addDomain(domain);
                _domainZoneMap[domain.domain] = zoneObj;
            };

            /**
             *
             * Process the results of a has_ns_authority results item
             *
             * @private
             *
             * @param {Object} resultItem
             * @returns {Domain} the updated Domain
             */
            Domains.prototype._processNSAuthResultItem = function _processNSAuthResultItem(resultItem) {
                var domainObj = this._getDomainObject(resultItem.domain);
                if (domainObj) {
                    domainObj.soaError = resultItem.error || undefined;
                    domainObj.hasNSAuthority = resultItem.local_authority.toString() === "1";
                    domainObj.nameservers = resultItem.nameservers;
                    this._addDomainToZone(domainObj, resultItem.zone);
                }
                return domainObj;
            };

            /**
             *
             * Process a results item based on recordType and add records and suggested records to domains
             *
             * @private
             *
             * @param {Object} processor for handling recordType example services/DKIMRecordProcessor
             * @param {Object} recordTypeResults api results for the specific api call {data:...}
             * @param {string} recordType record type being processed
             */
            Domains.prototype._processRecordTypeResults = function _processRecordTypeResults(processor, recordTypeResults, recordType) {

                var normalizedResults = processor.normalizeResults(recordTypeResults);

                if (recordType === "ptr") {
                    this._extractMailIPs(recordTypeResults);
                }

                var normalizedResultsData = normalizedResults.data;
                var processedResults = processor.processResultItems(normalizedResultsData);
                normalizedResultsData.forEach(function(normalizedResultItem, index) {
                    var domainObj = this._getDomainObject(normalizedResultItem.domain);
                    if (!domainObj) {
                        $log.debug("domain not found", normalizedResultItem);
                        return;
                    }
                    var domainRecords = processedResults[index];
                    var suggestedRecord = processor.generateSuggestedRecord(normalizedResultItem);
                    domainObj.setSuggestedRecord(recordType, suggestedRecord);

                    domainObj.setRecordDetails(recordType, normalizedResultItem.details || normalizedResultItem);

                    if (recordType === "spf") {
                        domainObj.setExpectedMatch(recordType, normalizedResultItem.expected);
                    }

                    domainRecords.forEach( domainObj.addRecord.bind(domainObj) );
                }, this);

            };

            function _reportDKIMValidityCacheUpdates(recordTypeResults) {
                var validityCacheUpdated = recordTypeResults.data.filter( function(item) {
                    return item.validity_cache_update === "set";
                } );

                if (validityCacheUpdated.length) {
                    var domains = validityCacheUpdated.map( function(item) {
                        return _.escape( _STRIP_DKIM_SUBDOMAIN(item.domain) );
                    } );

                    domains = _.sortBy( domains, function(d) {
                        return d.length;
                    } );

                    // “domains” shouldn’t be a long list. If it becomes
                    // so, we’ll need to chop this up so that it gives just
                    // a few domains and then says something like
                    // “… and N others”. That will avoid creating a big blob
                    // in what should normally be just an informative alert.
                    $alertService.add({
                        type: "info",
                        replace: false,
                        message: LOCALE.maketext("The system detected [quant,_1,domain,domains] whose [output,acronym,DKIM,DomainKeys Identified Mail] signatures were inactive despite valid [asis,DKIM] configuration. The system has automatically enabled [asis,DKIM] signatures for the following [numerate,_1,domain,domains]: [list_and_quoted,_2]", domains.length, domains),
                    });
                }
            }

            /**
             *
             * Process the results of the fetchMailRecords API
             *
             * @private
             *
             * @param {Array} results batch api results [{data:...},{data:...}] where the first is the result of the has_ns_authority call, and the rest are recordType related
             * @param {Array<String>} recordTypes record types requested during the fetchMailRecords API call
             */
            Domains.prototype._processMailRecordResults = function _processMailRecordResults(results, recordTypes) {
                var batchResultItems = results.data;

                var nsAuthResult = batchResultItems.shift();

                if (nsAuthResult.data) {
                    nsAuthResult.data.forEach(this._processNSAuthResultItem, this);
                }

                recordTypes = recordTypes ? recordTypes : this.getSupportedRecordTypes();
                var processors = this.getRecordProcessors();

                recordTypes.forEach(function(recordType, index) {
                    var recordTypeResults = batchResultItems[index];
                    var processor = processors[recordType];
                    this._processRecordTypeResults(processor, recordTypeResults, recordType);

                    if (recordType === "dkim") {
                        _reportDKIMValidityCacheUpdates(recordTypeResults);
                    }
                }, this);
            };

            /**
             *
             * API Wrapper to fetch the status of all mail records for a set of domains
             *
             * @public
             *
             * @param {Array<Domain>} domains array of Domain() objects for which to fetch records
             * @param {Array<String>} recordTypes array of record types for which to fetch records
             * @returns {Promise<void>} returns the promise, but does not return an results object. That data is updated on the domain objects.
             */
            Domains.prototype.fetchMailRecords = function fetchMailRecords(domains, recordTypes) {

                var self = this;

                if (domains.length === 0) {
                    return $q.resolve();
                }

                var start = new Date();
                var startTime = start.getTime();

                var apiCall = $apiInit.init("Batch", "strict");

                var flatDomains = {};
                domains.forEach(function(domain, index) {
                    return flatDomains["domain-" + index] = domain.domain;
                });

                var commands = [];

                commands.push($apiInit.buildBatchCommandItem("DNS", "has_local_authority", flatDomains));

                recordTypes = recordTypes ? recordTypes : this.getSupportedRecordTypes();
                var processors = this.getRecordProcessors();

                recordTypes.forEach(function(recordType) {
                    var processor = processors[recordType];
                    var apiName = processor.getValidateAPI();
                    commands.push($apiInit.buildBatchCommandItem(apiName.module, apiName.func, flatDomains));
                }, this);

                apiCall.addArgument("command", commands);

                // If there’s an in-progress fetch already, then abort it
                // because we know we don’t need its data.
                if (this._fetchMailRecordsPromise) {
                    $log.debug("Canceling prior record status load");
                    this._fetchMailRecordsPromise.cancelCpCall();
                }

                this._fetchMailRecordsPromise = this.promise(apiCall);

                return this._fetchMailRecordsPromise.then(function(result) {

                    var end = new Date();
                    var endTime = end.getTime();
                    $log.debug("Updating record statuses load took " + (endTime - startTime) + "ms for " + domains.length + " domains");
                    startTime = endTime;
                    self._processMailRecordResults(result, recordTypes);
                }).finally(function() {
                    delete self._fetchMailRecordsPromise;

                    var end = new Date();
                    var endTime = end.getTime();

                    $log.debug("Updating record statuses parsing took " + (endTime - startTime) + "ms for " + domains.length + " domains");
                });
            };

            /**
             *
             * Reset the records for a given domain, and poll for the records
             *
             * @public
             *
             * @param {Array<Domain>} domains array of domains for which to fetch records
             * @param {Array<string>} recordTypes array of record types for which to fetch records
             * @returns {Promise<void>} returns the promise, but does not return an results object. That data is updated on the domain objects.
             */
            Domains.prototype.validateAllRecords = function validateAllRecords(domains, recordTypes) {

                var self = this;
                recordTypes = recordTypes ? recordTypes : self.getSupportedRecordTypes();

                // Filter out domains already queued for a reload
                domains = domains.filter(function(domain) {
                    if (domain.reloadingIn) {
                        return false;
                    }
                    return true;
                });

                domains.forEach(function(domain) {
                    domain.resetRecordLoaded();
                }, self);

                return self.fetchMailRecords(domains, recordTypes).then(function() {
                    domains.forEach(function(domain) {
                        domain.setRecordsLoaded(recordTypes);
                    }, self);
                });

            };

            /**
             *
             * Returns a list of available processors for available record types. This is the key function for disabling record types.
             *
             * @public
             *
             * @returns {Object} returns object with keys representing record types, and value representing processor objects
             */
            Domains.prototype.getRecordProcessors = function recordProcessors() {

                var processors = {
                    "dkim": DKIMRecordProcessor,
                    "spf": SPFRecordProcessor
                };

                if ( PAGE.skipPTRLookups === undefined || !PAGE.skipPTRLookups ) {
                    processors.ptr = PTRRecordProcessor;
                }

                return processors;
            };

            /**
             *
             * Returns the currently supported record types.
             *
             * @public
             *
             * @returns {Array<strings>} array of supported record type strings
             */
            Domains.prototype.getSupportedRecordTypes = function getSupportedRecordTypes() {
                return Object.keys(this.getRecordProcessors());
            };

            /**
             *
             * Repair SPF records for a set of domains
             *
             * @public
             *
             * @param {Array<Domain>} domains array of domains to update records for
             * @param {Array<string>} records new SPF record strings to update
             * @returns <Promise<Object>> returns a promise and then an API results object
             */
            Domains.prototype.repairSPF = function repairSPF(domains, records) {
                var processors = this.getRecordProcessors();
                var processor = processors["spf"];
                var apiName = processor.getInstallAPI();

                var flatDomains = domains.map(function(domain) {
                    return domain.domain;
                });

                var apiCall = $apiInit.init(apiName.module, apiName.func);
                apiCall.addArgument("domain", flatDomains);
                apiCall.addArgument("record", records);

                return this.promise(apiCall);
            };


            /**
             * Present a warning that the change may not be reflected
             *
             * @param {string} domain
             */
            Domains.prototype.unreflectedChangeMessage = function unreflectedchangeMessage(domain) {
                var zoneEditorURL = PAGE.zoneEditorUrl;
                var message = "";
                message += LOCALE.maketext("Because this is not an authoritative nameserver for the domain “[_1]”, the current or suggested records will not reflect your changes.", domain);
                if (zoneEditorURL) {
                    message += " ";
                    message += LOCALE.maketext("Use the [output,url,_1,Zone Editor] to ensure that the system applied your changes.", zoneEditorURL + domain);
                }
                $alertService.add({
                    message: message,
                    type: "warning"
                });
            };

            /**
             *
             * Repair DKIM records for a set of domains
             *
             * @public
             *
             * @param {Array<Domain>} domains array of domains to update records for
             * @returns <Promise<Object>> returns a promise and then an API results object
             */
            Domains.prototype.repairDKIM = function repairDKIM(domains) {
                var processors = this.getRecordProcessors();
                var processor = processors["dkim"];
                var apiName = processor.getInstallAPI();

                var flatDomains = domains.map(function(domain) {
                    return domain.domain;
                });

                var apiCall = $apiInit.init(apiName.module, apiName.func);
                apiCall.addArgument("domain", flatDomains);

                return this.promise(apiCall);
            };

            /**
             *
             * Repair PTR records for a set of domains **current unsupported**
             *
             * @public
             *
             */
            Domains.prototype.repairPTR = function repairPTR(domain) {
                throw new Error("Installing PTR Records are not currently supported in this interface.");
            };

            /**
             *
             * Repair a record type for a single domain
             *
             * @public
             *
             * @param {Domain} domain domain to repair the record for
             * @param {String} recordType record type to repair
             * @param {String} newRecord new record, if setting a new record for the domain (SPF)
             * @returns {Promise<Object>} returns a promise and then the API result object
             */
            Domains.prototype.repairRecord = function repairRecord(domain, recordType, newRecord) {

                if (recordType === "spf") {
                    return this.repairSPF([domain], [newRecord]);
                } else if (recordType === "dkim") {
                    return this.repairDKIM([domain], [newRecord]);
                } else if (recordType === "ptr") {
                    return this.repairPTR([domain], [newRecord]);
                }

            };

            /**
             *
             * Called on success of a record repair
             *
             * @private
             *
             * @param {Domain} domainObj domain updated during the repair call
             * @param {String} recordType record type repaired during the repair call
             * @param {String} record resulting updated record
             */
            Domains.prototype._repairRecordSuccess = function _repairRecordSuccess(domainObj, recordType, record) {
                $alertService.success({
                    replace: false,
                    message: LOCALE.maketext("The system updated the “[_1]” record for “[_2]” to the following: [_3]", recordType.toUpperCase(), _.escape(domainObj.domain), "<pre>" + _.escape(record) + "</pre>")
                });
            };

            /**
             *
             * Called on failure of a record repair
             *
             * @private
             *
             * @param {Domain} domainObj domain updated during the repair call
             * @param {String} recordType record type repaired during the repair call
             * @param {String} error
             */
            Domains.prototype._repairRecordFailure = function _repairRecordSuccess(domainObj, recordType, error) {
                $alertService.add({
                    type: "error",
                    replace: false,
                    message: LOCALE.maketext("The system failed to update the “[_1]” record for “[_2]” because of an error: [_3]", recordType.toUpperCase(), _.escape(domainObj.domain), _.escape(error))
                });
            };

            Domains.prototype._interval = function _interval(func, interval, count) {
                return $interval(func, interval, count);
            };

            Domains.prototype._validateUntilSuccessComplete = function _validateUntilSuccessComplete(domainObj, successTypeRecords, waitAfter, startTime) {

                var self = this;

                $log.debug("[" + domainObj.domain + "] fetchMailRecords completed");

                var recordTypes = self.getSupportedRecordTypes();

                domainObj.setRecordsLoaded(recordTypes);
                var someFailed = successTypeRecords.some(function(recordType) {
                    return !domainObj.isRecordValid(recordType);
                });

                var timePassed = (new Date().getTime() - startTime) / 1000;

                $log.debug("[" + domainObj.domain + "] time passed since records set: " + timePassed);

                // If not, double waitAfter and wait that long to check again
                if (someFailed && timePassed < 120) {
                    $log.debug("[" + domainObj.domain + "] some failed, wait " + (waitAfter) + "s, and then try again.");

                    // Only bother alerting if it's been more than 5 seconds since the first call.
                    // A safety for the I/O issue found in COBRA-8775
                    if (timePassed > 5) {
                        $alertService.add({
                            type: "info",
                            replace: true,
                            message: LOCALE.maketext("The server records have not updated after [quant,_1,second,seconds]. The system will try again in [quant,_2,second,seconds].", Math.floor(timePassed), Math.floor(waitAfter))
                        });
                    }

                    domainObj.resetRecordLoaded();

                    domainObj.reloadingIn = waitAfter;

                    return self._interval(function() {
                        domainObj.reloadingIn--;
                    }, 1000, waitAfter).then(function() {
                        domainObj.reloadingIn = 0;
                        waitAfter *= 2;
                        $log.debug("[" + domainObj.domain + "] done waiting, trying again.");
                        return self.validateUntilSuccess(domainObj, successTypeRecords, waitAfter, startTime);
                    });
                } else {

                    if (!someFailed) {
                        $log.debug("[" + domainObj.domain + "] all records fixed.");
                        $alertService.success({
                            replace: true,
                            message: LOCALE.maketext("The system successfully updated the [asis,DNS] records.")
                        });
                    } else if (timePassed > 120) {
                        $log.debug("[" + domainObj.domain + "] more than 120s was taken to validate the change.");
                        $alertService.add({
                            type: "warning",
                            replace: true,
                            message: LOCALE.maketext("The system cannot verify that the record updated after 120 seconds.")
                        });
                    }

                    // If records are valid, we're done
                    domainObj.setRecordsLoaded(self.getSupportedRecordTypes());
                }
            };


            Domains.prototype.validateUntilSuccess = function validateUntilSuccess(domain, successTypeRecords, waitAfter, startTime) {
                var self = this;

                var domainObj = this._getDomainObject(domain);
                var recordTypes = self.getSupportedRecordTypes();

                $log.debug("[" + domain.domain + "] begin validateUntilSuccess @" + (waitAfter) + "s");

                return self.fetchMailRecords([domainObj], recordTypes).then(function() {
                    return self._validateUntilSuccessComplete(domainObj, successTypeRecords, waitAfter, startTime);
                });
            };

            Domains.prototype.getDomainZoneObject = function getDomainZoneObject(domain) {
                var domainObj = this._getDomainObject(domain);
                return this.findZoneByName(domainObj.zone) || false;
            };

            Domains.prototype._repairDomainComplete = function _repairDomainComplete(result, domain, recordTypes, records, skipValidation) {

                $log.debug("[" + domain.domain + "] beginning _repairDomainComplete.");

                var self = this;

                if (result.data) {
                    var recordsThatSucceeded = [];
                    result.data.forEach(function _processRecordResultObj(recordResultObj, index) {
                        var recordType = recordTypes[index];
                        var record = records[index];
                        var domainResultObj = recordResultObj.data[0];

                        $log.debug("[" + domainResultObj.domain + "] being parsed in _repairDomainComplete status: [" + domainResultObj.status + "].");

                        if (domainResultObj.status.toString() !== "1") {
                            this._repairRecordFailure(domain, recordType, domainResultObj.msg);
                        } else {
                            recordsThatSucceeded.push(recordType);
                            this._repairRecordSuccess(domain, recordType, record);
                        }
                    }, this);

                    if (skipValidation) {
                        $log.debug("[" + domain.domain + "] does not have NS Authority. Do not continue validation check");
                        return;
                    }

                    if (recordsThatSucceeded.length) {
                        $log.debug("[" + domain.domain + "] some records succeeeded.", recordsThatSucceeded.join(","));

                        var startTime = new Date().getTime();

                        return self.validateUntilSuccess(domain, recordsThatSucceeded, 5, startTime);
                    } else {
                        return self.validateAllRecords([domain]);
                    }
                }

            };

            Domains.prototype.repairDomain = function repairDomain(domain, recordTypes, records, skipValidation) {

                recordTypes = recordTypes.slice();
                records = records.slice();

                var self = this;

                var domainObj = this._getDomainObject(domain);

                // Lock the Zone
                var zoneObj = this.findZoneByName(domainObj.zone);
                zoneObj.lock(domainObj);
                $log.debug("[" + domainObj.domain + "] locking zone: ", zoneObj.zone);

                $log.debug("[" + domainObj.domain + "] beginning repairDomain.");

                // Only reset it if we have auth, because otherwise it won't come back
                if (!skipValidation) {
                    domainObj.resetRecordLoaded();
                }

                $log.debug("[" + domainObj.domain + "] resetting loaded records.");

                // Start the Repair - Batch is serial, so this is fine to do
                var apiCall = $apiInit.init("Batch", "strict");
                var processors = self.getRecordProcessors();

                var commands = recordTypes.map(function(recordType, index) {
                    var record = records[index];
                    var processor = processors[recordType];
                    var apiName = processor.getInstallAPI();
                    $log.debug("[" + domainObj.domain + "] adding batch command for “" + recordType + "”.");
                    return $apiInit.buildBatchCommandItem(apiName.module, apiName.func, { "domain": domainObj.domain, record: record });
                });

                apiCall.addArgument("command", commands);

                return self.promise(apiCall).then(function(result) {
                    $log.debug("[" + domainObj.domain + "] batch command completed.");
                    zoneObj.unlock();
                    return self._repairDomainComplete(result, domainObj, recordTypes, records, skipValidation);
                });
            };

            /**
             *
             * Process the API result for fetchPrivateDKIMKey
             *
             * @private
             *
             * @param {Object} result API results object {data:...}
             * @returns first result of API results.data array
             */
            Domains.prototype._processGetPrivateDKIMKey = function _processGetPrivateDKIMKey(result) {
                return result.data.pop();
            };

            /**
             *
             * Get the private DKIM key for a domain
             *
             * @public
             *
             * @param {Domain} domain domain to request the DKIM key for
             * @returns {Promise<Object>} DKIM Key object {pem:...,domain:...}
             */
            Domains.prototype.fetchPrivateDKIMKey = function fetchPrivateDKIMKey(domain) {
                var domainObj = this._getDomainObject(domain);

                var apiCall = $apiInit.init("EmailAuth", "fetch_dkim_private_keys");
                apiCall.addArgument("domain", domainObj.domain);

                return this.promise(apiCall).then(this._processGetPrivateDKIMKey);
            };

            /**
             *
             * Get the top most current record for a domain and record type
             *
             * @public
             *
             * @param {Domain} domain domain to get the record from
             * @param {String} recordType record type to fetch the record for
             * @returns {String} returns the string record or an empty string
             */
            Domains.prototype.getCurrentRecord = function getCurrentRecord(domain, recordType) {

                var domainObj = this._getDomainObject(domain);
                return domainObj.getCurrentRecord(recordType);

            };

            Domains.prototype.getNoAuthorityMessage = function getNoAuthorityMessage(domainObj, recordType) {
                var nameserversHtml = domainObj.nameservers.map( _.escape );

                var message;

                if (domainObj.nameservers.length) {
                    message = LOCALE.maketext("This system does not control [asis,DNS] for the “[_1]” domain.", domainObj.domain);
                } else {
                    message = LOCALE.maketext("This system does not control [asis,DNS] for the “[_1]” domain and the system did not find any authoritative nameservers for this domain.", domainObj.domain);
                }

                if (recordType === "spf" || recordType === "dkim") {

                    // Handle differently for spf
                    message += " ";
                    message += "<strong>";
                    message += LOCALE.maketext("You can install the suggested “[_1]” record locally. However, this server is not the authoritative nameserver. If you install this record, this change will not be effective.", recordType.toUpperCase());
                    message += "</strong>";
                }

                message += " ";

                if (domainObj.nameservers.length) {
                    message += LOCALE.maketext("Contact the person responsible for the [list_and_quoted,_3] [numerate,_2,nameserver,nameservers] and request that they update the “[_1]” record with the following:", recordType.toUpperCase(), domainObj.nameservers.length, nameserversHtml);
                } else {
                    message += LOCALE.maketext("Contact your domain registrar to verify this domain’s registration.");
                }

                return message;

            };

            /**
             *
             * API Wrapper to obtain the helo record for a domain
             *
             * @param {Domain} domain domain to request the helo record for
             * @returns {Promise} get_mail_helo_ip promise
             */
            Domains.prototype.fetchMailHeloIP = function fetchMailHeloIP(domain) {

                var domainObj = this._getDomainObject(domain);

                var apiCall = $apiInit.init("EmailAuth", "get_mail_helo_ip");
                apiCall.addArgument("domain", domainObj.domain);

                return this.promise(apiCall).then(this._processMailHeloResult);

            };

            Domains.prototype.localDKIMExists = function localDKIMExists(domain) {
                var recordType = "dkim";

                if (domain.isRecordValid(recordType)) {
                    return true;
                }

                var record = domain.getSuggestedRecord(recordType);
                if (record.value) {
                    return true;
                }
                return false;
            };

            Domains.prototype.ensureLocalDKIMKeyExists = function ensureLocalDKIMKeyExists(domain) {
                var self = this;
                var apiCall = $apiInit.init("EmailAuth", "ensure_dkim_keys_exist");

                apiCall.addArgument("domain", domain.domain);

                return self.promise(apiCall).then(function(results) {
                    var data = results.data;
                    var domainResult = data.pop();
                    if (domainResult.status.toString() === "1") {
                        return self.fetchMailRecords([domain]);
                    } else {
                        return $alertService.add({
                            type: "error",
                            message: _.escape(domainResult.msg),
                        });
                    }
                });
            };

            // To be called whenever a view changes so that pending
            // “load” API calls can be canceled or abandoned.
            Domains.prototype.markViewLoad = function() {
                if (this._fetchMailRecordsPromise) {
                    this._fetchMailRecordsPromise.cancelCpCall();
                }
            };

            return new Domains();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.value("PAGE", PAGE);
        app.value("DOMAIN_TYPE_CONSTANTS", domainFactory.getTypeConstants());
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "namespace": MODULE_NAMESPACE
        };
    }
);
