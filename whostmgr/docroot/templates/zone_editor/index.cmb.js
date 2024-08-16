/*
# zone_editor/services/features.js                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/features',[
        "angular"
    ],
    function(angular) {

        "use strict";

        var MODULE_NAMESPACE = "whm.zoneEditor.services.features";
        var SERVICE_NAME = "FeaturesService";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = function(defaultInfo) {

            var store = {};

            store.dnssec = false;
            store.mx = false;
            store.simple = false;
            store.advanced = false;
            store.whmOnly = false;

            store.init = function() {
                store.dnssec = defaultInfo.has_dnssec_feature;
                store.mx = defaultInfo.has_mx_feature;
                store.simple = defaultInfo.has_simple_feature;
                store.advanced = defaultInfo.has_adv_feature;
                store.whmOnly = defaultInfo.has_whmOnly_feature;
            };

            store.init();

            return store;
        };
        app.factory(SERVICE_NAME, ["defaultInfo", SERVICE_FACTORY]);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);

/*
# services/recordTypes.js                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/services/recordTypes',[
        "angular",
        "lodash",
        "app/services/features",
    ],
    function(angular, _, FeaturesService) {

        "use strict";

        var MODULE_NAMESPACE = "whm.zoneEditor.services.recordTypes";
        var SERVICE_NAME = "RecordTypesService";
        var MODULE_REQUIREMENTS = [ FeaturesService.namespace ];
        var SERVICE_INJECTABLES = [ FeaturesService.serviceName, "$q", "RECORD_TYPES" ];

        var SERVICE_FACTORY = function($featuresService, $q, RECORD_TYPES) {

            function _getRecordTypes() {
                return Object.keys(RECORD_TYPES).filter(function _filterRecordType(recordTypeKey) {
                    var recordType = RECORD_TYPES[recordTypeKey];
                    return recordType.featureNeeded.some(function _isFeatureEnabled(feature) {
                        return $featuresService[feature];
                    });
                }).map(function _buildRecordObj(recordTypeKey) {
                    var recordType = _.assign(RECORD_TYPES[recordTypeKey], {
                        type: recordTypeKey
                    });
                    return recordType;
                }).sort(function _sort(a, b) {
                    return a.priority - b.priority;
                });
            }

            var Service = function() {};

            _.assign(Service.prototype, {

                _records: _getRecordTypes(),

                get: function get() {
                    return $q.resolve(this._records);
                }

            });

            return new Service();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);

/*
# zone_editor/services/domains.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/domains',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/util/httpStatus",
        "cjt/core",
        "cjt/io/whm-v1",
    ],
    function(angular, _, LOCALE, API, APIREQUEST, HTTP_STATUS, CJT) {

        "use strict";

        var SERVICE_NAME = "Domains";
        var MODULE_NAMESPACE = "whm.zoneEditor.services.domains";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = function($q, defaultInfo) {

            var store = {};

            store.domains = [];

            store.fetch = function() {

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "listzones");

                return store._promise(apiCall)
                    .then(function(response) {
                        response = response.parsedResponse;

                        if (response.status) {
                            if (response.data !== null) {
                                store.domains = response.data.map(function(domain) {
                                    return {
                                        domain: domain.domain
                                    };
                                });
                            } else {
                                store.domains = [];
                            }

                            return $q.resolve(store.domains);
                        } else {
                            return $q.reject(response);
                        }
                    })
                    .catch(store._parseAPIFailure);
            };

            store.init = function() {
                store.domains = defaultInfo.domains.map(function(domain) {
                    return {
                        domain: domain
                    };
                });
            };

            store._promise = function(apiCall) {
                return $q.when(API.promise(apiCall.getRunArguments()));
            };

            store._parseAPIFailure = function(response) {
                if (!response.status) {
                    return $q.reject(response.error);
                }
                return $q.reject(store.request_failure_message(response.status));
            };

            /**
             * Generates the error text for when an API request fails.
             *
             * @method request_failure_message
             * @param  {Number|String} status   A relevant status code.
             * @return {String}                 The text to be presented to the user.
             */
            store.request_failure_message = function(status) {
                var message = LOCALE.maketext("The API request failed with the following error: [_1] - [_2].", status, HTTP_STATUS.convertHttpStatusToReadable(status));
                if (status === 401 || status === 403) {
                    message += " " + LOCALE.maketext("Your session may have expired or you logged out of the system. [output,url,_1,Login] again to continue.", CJT.getLoginPath());
                }

                return message;
            };

            store.init();

            return store;
        };

        app.factory(SERVICE_NAME, ["$q", "defaultInfo", SERVICE_FACTORY]);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);

/*
# zone_editor/services/zones.js                                   Copyright 2022 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* define: false */

define(
    'app/services/zones',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/util/httpStatus",
        "cjt/core",
        "cjt/util/base64",
        "app/services/recordTypes",
        "cjt/io/whm-v1",
    ],
    function(angular, _, LOCALE, API, APIREQUEST, HTTP_STATUS, CJT, BASE64, RecordTypesService) {

        "use strict";


        var MODULE_NAMESPACE = "whm.zoneEditor.services.zones";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_NAME = "Zones";
        var SERVICE_INJECTABLES = ["$q", "$log", "alertService", RecordTypesService.serviceName];
        var SERVICE_FACTORY = function($q, $log, $alertService, $recordTypes) {

            var store = {};

            store.zones = [];
            store.generated_domains = [];

            function _saveRecords(zone, records, serial) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "mass_edit_dns_zone");
                apiCall.addArgument("zone", zone);
                apiCall.addArgument("serial", serial);

                // adding MX from the quick add options in the domain list does not provide a "name" input- without the trailing dot added the parsing of the records believes the record name to actually be a subdomain
                records.forEach(function(record) {
                    if (record.record_type === "MX") {
                        if (record.dname === zone) {
                            record.dname = record.dname + ".";
                        }
                    }
                });

                var add = records.filter(function(record) {
                    return record.is_new;
                });
                var edit = records.filter(function(record) {
                    return !record.is_new;
                });

                // remove unneeded property before submission to API
                add.forEach(function(record) {
                    delete record.is_new;
                });

                edit.forEach(function(record) {
                    delete record.is_new;
                });

                var jsonAdd = add.map(function(record) {
                    return JSON.stringify(record);
                });
                apiCall.addArgument("add", jsonAdd);

                var jsonEdit = edit.map(function(record) {
                    return JSON.stringify(record);
                });
                apiCall.addArgument("edit", jsonEdit);

                return store._promise(apiCall)
                    .then(store._parseAPISuccess)
                    .catch(store._parseAPIFailure);
            }

            /**
             * Save new or modified zone records
             * @param zone - name of zone
             * @param records - records to update or create
             * @param serial - serial number of record
             * @returns - a promise resolving to true if successful, or an error
             */
            store.saveRecords = function(zone, records, serial) {

                // the serial and default TTL will not exist if this request comes from any of the 'quick add' records on the domain lister page
                // SOA record  and default TTL for given zone must be fetched first
                if (!serial) {
                    return store.fetch(zone)
                        .then(function(response) {
                            var soaRec = response.parsedZoneData.filter(function(record) {
                                return record.record_type === "SOA";
                            });
                            soaRec = soaRec[0];
                            var serial = parseInt(soaRec.serial, 10);
                            records[0]["ttl"] = parseInt(response.defaultTTL, 10);
                            return _saveRecords(zone, records, serial);
                        });
                } else {
                    return _saveRecords(zone, records, serial);
                }
            };

            /**
             * Get the raw zone file content in Base64
             * @param zone - the name of the zone to get records for
             * @returns - decoded Base64 raw zone file contents
             */
            store.exportZoneFile = function(zone) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "export_zone_files");
                apiCall.addArgument("zone", zone);

                return store._promise(apiCall).then(function(response) {
                    var parsedResponse = response.parsedResponse;
                    if (parsedResponse.status) {
                        var b64 = parsedResponse.data[0].text_b64;
                        var decoded = BASE64.decodeUTF8(b64);
                        return decoded;
                    } else {
                        return $q.reject(response);
                    }
                }).catch(store._parseAPIFailure);
            };

            /**
             * Trim the trailing dot (.) if present. This is used at places where a qualified
             * domain value is sent to the ‘addzonerecord’ API call because the API appends the dot (.)
             * again.
             *
             * @param value - the DNS type value that could be a qualified domain name.
             *
             * @return value without the trailing dot (.)
             */
            store.trimTrailingDot = function(value) {
                value = value.replace(/\.$/, "");
                return value;
            };

            /**
             * Fetch all DNZ Zone Records for a given zone
             * @param zone - name of zone to get records for
             * @returns - an array of parsed and decoded zone record data
             */
            store.fetch = function(zone) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "parse_dns_zone");
                apiCall.addArgument("zone", zone);

                return store._promise(apiCall)
                    .then(function(response) {
                        var parsedResponse = response.parsedResponse;
                        if (parsedResponse.status) {
                            var defaultTTL;
                            var record;
                            var parsedZoneData = [];
                            for (var i = 0, len = parsedResponse.data.length; i < len; i++) {
                                record = parsedResponse.data[i];
                                if (record.type === "record") {
                                    record["txtdata"] = [];
                                    record["name"] = BASE64.decodeUTF8(record.dname_b64);
                                    if (record.name !== zone + ".") {
                                        record.name = record.name + "." + zone + ".";
                                    }

                                    // Helps QA to identify records.
                                    record["id_prefix"] = record.record_type.toLowerCase();
                                    record.data_b64.forEach(function(data) {
                                        record.txtdata.push(BASE64.decodeUTF8(data));
                                    });

                                    switch (record.record_type) {
                                        case "AFSDB":
                                            record["subtype"] = record.txtdata[0];
                                            record["hostname"] = store.trimTrailingDot(record.txtdata[1]);
                                            break;
                                        case "CAA":
                                            record["flag"] = record.txtdata[0];
                                            record["tag"] = record.txtdata[1];
                                            record["value"] = record.txtdata[2];
                                            break;
                                        case "DS":
                                            record["keytag"] = record.txtdata[0];
                                            record["algorithm"] = record.txtdata[1];
                                            record["digtype"] = record.txtdata[2];
                                            record["digest"] = record.txtdata[3];
                                            break;
                                        case "HINFO":
                                            record["cpu"] = record.txtdata[0];
                                            record["os"] = record.txtdata[1];
                                            break;
                                        case "LOC":

                                            var latSplit = record.txtdata[0].split("N");
                                            var latPart;
                                            if (latSplit.length < 2) {
                                                latSplit = record.txtdata[0].split("S");
                                                latPart = latSplit[0];
                                                record["latitude"] = latPart + " S".trim();
                                            } else {
                                                latPart = latSplit[0];
                                                record["latitude"] = latPart + " N".trim();
                                            }

                                            var longSplit = latSplit[1].split("E");
                                            var longPart;
                                            if (longSplit.length < 2) {
                                                longSplit = latSplit[1].split("W");
                                                longPart = longSplit[0];
                                                record["longitude"] = longPart + " W".trim();
                                            } else {
                                                longPart = longSplit[0];
                                                record["longitude"] = longPart + " E".trim();
                                            }

                                            var dataSplit = longSplit[1];
                                            dataSplit = dataSplit.trim().split(" ");

                                            // /\.$/, ""
                                            record["altitude"] = dataSplit[0];
                                            record["size"] = dataSplit[1];
                                            record["horiz_pre"] = dataSplit[2];
                                            record["vert_pre"] = dataSplit[3];

                                            record.altitude = record.altitude.replace(/m$/, "");
                                            record.size = record.size.replace(/m$/, "");
                                            record.horiz_pre = record.horiz_pre.replace(/m$/, "");
                                            record.vert_pre = record.vert_pre.replace(/m$/, "");
                                            break;
                                        case "MX":
                                            record["priority"] = record.txtdata[0];
                                            record["exchange"] = store.trimTrailingDot(record.txtdata[1]);
                                            break;
                                        case "NAPTR":
                                            record["order"] = record.txtdata[0];
                                            record["preference"] = record.txtdata[1];
                                            record["flags"] = record.txtdata[2];
                                            record["service"] = record.txtdata[3];
                                            record["regexp"] = record.txtdata[4];
                                            record["replacement"] = store.trimTrailingDot(record.txtdata[5]);
                                            break;
                                        case "RP":
                                            record["mbox"] = store.trimTrailingDot(record.txtdata[0]);
                                            record["txtdname"] = store.trimTrailingDot(record.txtdata[1]);
                                            break;
                                        case "SOA":
                                            record["serial"] = record.txtdata[2];
                                            record["mname"] = store.trimTrailingDot(record.txtdata[0]);
                                            record["retry"] = record.txtdata[4];
                                            record["refresh"] = record.txtdata[3];
                                            record["expire"] = record.txtdata[5];
                                            record["rname"] = store.trimTrailingDot(record.txtdata[1]);
                                            break;
                                        case "SRV":
                                            record["priority"] = record.txtdata[0];
                                            record["weight"] = record.txtdata[1];
                                            record["port"] = record.txtdata[2];
                                            record["target"] = store.trimTrailingDot(record.txtdata[3]);
                                            break;
                                        case "CNAME":
                                            record["record"] = store.trimTrailingDot(record.txtdata[0]);
                                            break;
                                        default:
                                            record["record"] = record.txtdata[0];
                                            break;
                                    }

                                    parsedZoneData.push(record);
                                } else if (record.type === "control") {
                                    defaultTTL = BASE64.decodeUTF8(record.text_b64);
                                    defaultTTL = defaultTTL.split(" ");
                                    defaultTTL = defaultTTL[1];
                                }
                            }
                            return {
                                parsedZoneData: parsedZoneData,
                                defaultTTL: defaultTTL,
                            };

                        } else {
                            return $q.reject(parsedResponse);
                        }
                    }).catch(store._parseAPIFailure);
            };

            function _removeZoneRecord(zone, line, serial) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "mass_edit_dns_zone");
                apiCall.addArgument("zone", zone);
                apiCall.addArgument("serial", serial);
                apiCall.addArgument("remove", line);

                return store._promise(apiCall)
                    .then(store._parseAPISuccess)
                    .catch(store._parseAPIFailure);
            }

            /**
             * Remove a record based on the type.
             * NOTE: After removing a record, we need to fetch the list of records from the
             * server since the api calls do some special serialization of the records.
             *
             * @param domain - the domain on which the record should be created
             * @param record - the record object we are sending. the fields in the object
             *                  depend on the type of record.
             * @return Promise
             */
            store.remove_zone_record = function(domain, line, serial) {
                return _removeZoneRecord(domain, line, serial);
            };

            store._promise = function(apiCall) {
                return $q.when(API.promise(apiCall.getRunArguments()));
            };

            store._parseAPIFailure = function(response) {
                if (!response.status) {
                    return $q.reject(response.error);
                }
                return $q.reject(store.request_failure_message(response.status));
            };

            store._parseAPISuccess = function(response) {
                response = response.parsedResponse;
                if (response.status) {
                    return true;
                } else {
                    return $q.reject(response);
                }
            };

            store.reset_zone = function(domain) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "resetzone");
                apiCall.addArgument("domain", domain);

                return store._promise(apiCall)
                    .then(store._parseAPISuccess)
                    .catch(store._parseAPIFailure);
            };

            store.fetch_generated_domains = function(domain, force) {
                store.generated_domains = {};
                return $q.when(store.generated_domains);
            };

            store.format_zone_name = function(domain, zoneName) {
                var name = zoneName;
                if (!angular.isDefined(name) || name === null || name === "") {
                    return "";
                }

                // add a dot at the end of the name, if needed
                if (zoneName.charAt(zoneName.length - 1) !== ".") {
                    name += ".";
                }

                // return what we have if a domain is not specified
                if (!angular.isDefined(domain) || domain === null || domain === "") {
                    return name;
                }

                // add the domain, if it does not already exist
                var domainPart = domain + ".";
                var endOfZoneName = name.slice(domainPart.length * -1);
                if (endOfZoneName.toLowerCase() !== domainPart.toLowerCase()) {
                    name += domainPart;
                }

                return name;
            };

            /**
             * Generates the error text for when an API request fails.
             *
             * @method request_failure_message
             * @param  {Number|String} status   A relevant status code.
             * @return {String}                 The text to be presented to the user.
             */
            store.request_failure_message = function(status) {
                var message = LOCALE.maketext("The API request failed with the following error: [_1] - [_2].", status, HTTP_STATUS.convertHttpStatusToReadable(status));
                if (status === 401 || status === 403) {
                    message += " " + LOCALE.maketext("Your session may have expired or you logged out of the system. [output,url,_1,Login] again to continue.", CJT.getLoginPath());
                }

                return message;
            };

            return store;
        };
        SERVICE_INJECTABLES.push(SERVICE_FACTORY);
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            namespace: MODULE_NAMESPACE,
            serviceName: SERVICE_NAME,
            class: SERVICE_FACTORY,
        };
    }
);

/*
# models/dynamic_table.js                         Copyright(c) 2020 cPanel, L.L.C# cpanel - base/sharedjs/zone_editor/models/dynamic_table.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'shared/js/zone_editor/models/dynamic_table',[
        "lodash",
        "cjt/util/locale",
    ],
    function(_, LOCALE) {

        "use strict";

        var PAGE_SIZES = [10, 20, 50, 100, 500, 1000];
        var DEFAULT_PAGE_SIZE = 100;

        // sanity check
        if (!PAGE_SIZES.includes(DEFAULT_PAGE_SIZE)) {
            throw "default not in page sizes";
        }

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
            this.quickFilterFunction = void 0;

            this.meta = {
                sortBy: "",
                sortDirection: "asc",
                maxPages: 0,
                totalItems: this.items.length,
                pageNumber: 1,
                pageSize: DEFAULT_PAGE_SIZE,
                pageSizes: PAGE_SIZES,
                start: 0,
                limit: 0,
                filterValue: "",
                quickFilterValue: "",
            };
        }

        DynamicTable.PAGE_SIZES         = PAGE_SIZES;
        DynamicTable.DEFAULT_PAGE_SIZE  = DEFAULT_PAGE_SIZE;

        /**
         * Set the filter function to be used for searching the table
         *
         * @method loadData
         * @param {Array} data - an array of objects representing the data to display
         */
        DynamicTable.prototype.loadData = function(data) {
            if (!_.isArray(data)) {
                throw "Developer Exception: loadData requires an array";
            }

            this.items = data;

            for (var i = 0, len = this.items.length; i < len; i++) {
                if (!_.isObject(this.items[i])) {
                    throw "Developer Exception: loadData requires an array of objects";
                }

                // add a unique id to each piece of data
                this.items[i]._id = i.toString();

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
            if (!_.isFunction(func)) {
                throw "Developer Error: setFilterFunction requires a function";
            }

            this.filterFunction = func;
        };

        /**
         * Set the quick filter function to be used with quick filters, which
         * are a predefined set of filter values
         *
         * @method setQuickFilterFunction
         * @param {Function} func - a function that can be used to filter data
         * @note The function passed to this function must
         * - return a boolean
         * - accept the following args: an item object and the search text
         */
        DynamicTable.prototype.setQuickFilterFunction = function(func) {
            if (!_.isFunction(func)) {
                throw "Developer Error: setQuickFilterFunction requires a function";
            }

            this.quickFilterFunction = func;
        };


        /**
         * Set the filter function to be used for searching the table
         *
         * @method setSort
         * @param {String} by - the field you want to sort on
         * @param {String} direction - the direction you want to sort, "asc" or "desc"
         */
        DynamicTable.prototype.setSort = function(by, direction) {
            if (!_.isUndefined(by)) {
                this.meta.sortBy = by;
            }

            if (!_.isUndefined(direction)) {
                this.meta.sortDirection = direction;
            }
        };

        /**
         * Get the table metadata
         *
         * @method getMetadata
         * @return {Object} The metadata for the table. We return a
         * reference here so that callers can update the object and
         * changes can easily be propagated.
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
            if (!_.isUndefined(item)) {
                if (item.selected) {

                    // make sure this item is not already in the list
                    if (this.selected.indexOf(item._id) !== -1) {
                        return;
                    }

                    this.selected.push(item._id);

                    // Sync 'Select All' checkbox status when a new selction/unselection is made.
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

        function _isExisting(item) {
            return !item.is_new || (item.is_new === "0");
        }

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
            if (this.meta.filterValue !== null &&
                this.meta.filterValue !== void 0 &&
                this.meta.filterValue !== "" &&
                _.isFunction(this.filterFunction)) {
                filtered = this.items.filter(function(item) {
                    return _isExisting(item) && self.filterFunction(item, self.meta.filterValue);
                });
            } else {
                filtered = this.items.filter(_isExisting);
            }

            // filter list based on the quick filter
            if (this.meta.quickFilterValue !== null &&
                this.meta.quickFilterValue !== void 0 &&
                this.meta.quickFilterValue !== "" &&
                _.isFunction(this.quickFilterFunction)) {
                filtered = filtered.filter(function(item) {
                    return self.quickFilterFunction(item, self.meta.quickFilterValue);
                });
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

            // Clear the 'Select All' checkbox if at least one row is not selected.
            this.allDisplayedRowsSelected = (filtered.length > 0) && (countNonSelected === 0);

            this.filteredList = this.items.filter(
                function(item) {
                    return !_isExisting(item);
                }
            ).concat(filtered);

            return this.filteredList;
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
# cpanel - whostmgr/docroot/templates/zone_editor/services/page_data_service.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/page_data_service',[
        "angular",
        "shared/js/zone_editor/models/dynamic_table",
    ],
    function(angular, DynamicTable) {

        "use strict";

        // Fetch the current application
        var MODULE_NAMESPACE = "whm.zoneEditor.services.pageDataService";
        var SERVICE_NAME = "pageDataService";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = function() {

            return {

                /**
                 * Helper method to remodel the default data passed from the backend
                 * @param  {Object} defaults - Defaults object passed from the backend
                 * @return {Object}
                 */
                prepareDefaultInfo: function(defaults) {
                    defaults.has_adv_feature = defaults.has_adv_feature || false;
                    defaults.has_simple_feature = defaults.has_simple_feature || false;
                    defaults.has_dnssec_feature = defaults.has_dnssec_feature || false;
                    defaults.has_mx_feature = defaults.has_mx_feature || false;
                    defaults.domains = defaults.domains || [];
                    defaults.otherRecordsInterface = defaults.otherRecordsInterface || false;

                    var pageSizeOptions = DynamicTable.PAGE_SIZES;
                    if (typeof defaults.zones_per_page !== "number") {
                        defaults.zones_per_page = parseInt(defaults.zones_per_page, 10);
                    }
                    if (!defaults.zones_per_page || pageSizeOptions.indexOf(defaults.zones_per_page) === -1 ) {
                        defaults.zones_per_page = DynamicTable.DEFAULT_PAGE_SIZE;
                    }

                    if (typeof defaults.domains_per_page !== "number") {
                        defaults.domains_per_page = parseInt(defaults.domains_per_page, 10);
                    }
                    if (!defaults.domains_per_page || pageSizeOptions.indexOf(defaults.domains_per_page) === -1 ) {
                        defaults.domains_per_page = DynamicTable.DEFAULT_PAGE_SIZE;
                    }

                    defaults.isRTL = defaults.isRTL || false;
                    return defaults;
                },

            };
        };

        /**
         * Setup the domainlist models API service
         */
        app.factory(SERVICE_NAME, [ SERVICE_FACTORY ]);

        return {
            class: SERVICE_FACTORY,
            serviceName: SERVICE_NAME,
            namespace: MODULE_NAMESPACE,
        };
    }
);

/*
# zone_editor/directives/convert_to_full_record_name.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define(
    'shared/js/zone_editor/directives/convert_to_full_record_name',[
        "angular"
    ],
    function(angular) {

        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.directives.convertToFullRecordName";
        var app = angular.module(MODULE_NAMESPACE, []);
        app.directive("convertToFullRecordName",
            ["Zones",
                function(Zones) {
                    return {
                        restrict: "A",
                        require: "ngModel",
                        scope: {
                            domain: "="
                        },
                        link: function(scope, element, attrs, ngModel) {

                        // we cannot work without ngModel
                            if (!ngModel) {
                                return;
                            }

                            // eslint-disable-next-line camelcase
                            function format_zone(eventName) {
                                var fullRecordName = Zones.format_zone_name(scope.domain, ngModel.$viewValue);
                                if (fullRecordName !== ngModel.$viewValue) {
                                    ngModel.$setViewValue(fullRecordName, eventName);
                                    ngModel.$render();
                                }
                            }

                            element.on("blur", function() {
                                format_zone("blur");
                            });

                            // trigger on Return/Enter
                            element.on("keydown", function(event) {
                                if (event.keyCode === 13) {
                                    format_zone("keydown");
                                }
                            });
                        }
                    };
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };

    }
);

/*
# zone_editor/views/domain_selection.js              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/* jshint -W100 */

define(
    'shared/js/zone_editor/views/domain_selection',[
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "shared/js/zone_editor/models/dynamic_table",
        "app/services/features",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/pageSizeButtonDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/filters/qaSafeIDFilter",
        "cjt/validator/ip-validators",
        "cjt/validator/domain-validators",
        "cjt/services/viewNavigationApi",
        "cjt/services/cpanel/nvDataService",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "shared/js/zone_editor/directives/convert_to_full_record_name",
    ],
    function(angular, _, CJT, LOCALE, DynamicTable, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.domainSelection";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.config([
            "$animateProvider",
            function($animateProvider) {
                $animateProvider.classNameFilter(/^((?!no-animate).)*$/);
            },
        ]);

        app.controller(
            "ListDomainsController",
            [
                "$q",
                "$location",
                "$routeParams",
                "Domains",
                "Zones",
                "$uibModal",
                "viewNavigationApi",
                FeaturesService.serviceName,
                "defaultInfo",
                "nvDataService",
                "alertService",
                function(
                    $q,
                    $location,
                    $routeParams,
                    Domains,
                    Zones,
                    $uibModal,
                    viewNavigationApi,
                    Features,
                    defaultInfo,
                    nvDataService,
                    alertService) {

                    var list = this;

                    list.ui = {};
                    list.ui.is_loading = false;
                    list.domains = [];

                    list.Features = Features;

                    list.modal = {};
                    list.modal.instance = null;
                    list.modal.title = "";
                    list.modal.name_label = LOCALE.maketext("Name");
                    list.modal.cname_label = "CNAME";
                    list.modal.address_label = LOCALE.maketext("Address");
                    list.modal.exchanger_label = LOCALE.maketext("Destination");
                    list.modal.exchanger_placeholder = LOCALE.maketext("Fully qualified domain name");
                    list.modal.priority_label = LOCALE.maketext("Priority");
                    list.modal.priority_placeholder = LOCALE.maketext("Integer");
                    list.modal.create_a_record = LOCALE.maketext("Add an [asis,A] Record");
                    list.modal.create_cname_record = LOCALE.maketext("Add a [asis,CNAME] Record");
                    list.modal.create_mx_record = LOCALE.maketext("Add an [asis,MX] Record");
                    list.modal.cancel_label = LOCALE.maketext("Cancel");
                    list.modal.required_msg = LOCALE.maketext("This field is required.");

                    list.loading_error = false;
                    list.loading_error_message = "";

                    var table = new DynamicTable();
                    table.setSort("domain");

                    function searchFunction(item, searchText) {
                        return item.domain.indexOf(searchText) !== -1;
                    }
                    table.setFilterFunction(searchFunction);

                    list.meta = table.getMetadata();
                    list.filteredList = table.getList();
                    list.paginationMessage = table.paginationMessage;
                    list.meta.pageSize = defaultInfo.domains_per_page;
                    list.render = function() {
                        list.filteredList = table.populate();
                    };
                    list.sortList = function() {
                        list.render();
                    };
                    list.selectPage = function() {
                        list.render();
                    };
                    list.selectPageSize = function() {
                        list.render();
                        if (defaultInfo.domains_per_page !== list.meta.pageSize) {
                            nvDataService.setObject({ domains_per_page: list.meta.pageSize })
                                .then(function() {
                                    defaultInfo.domains_per_page = list.meta.pageSize;
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                });
                        }
                    };
                    list.searchList = function() {
                        list.render();
                    };

                    list.refresh = function() {
                        return load(true);
                    };

                    list.aRecordModalController = function($uibModalInstance, domain) {
                        var ar = this;
                        ar.domain = domain;
                        ar.modal_header = LOCALE.maketext("Add an [asis,A] Record for “[_1]”", domain);
                        ar.name_label = list.modal.name_label;
                        ar.address_label = list.modal.address_label;
                        ar.submit_label = list.modal.create_a_record;
                        ar.cancel_label = list.modal.cancel_label;
                        ar.required_msg = list.modal.required_msg;
                        ar.zone_name_placeholder = Zones.format_zone_name(domain, "example");

                        ar.resource = {
                            dname: "",
                            ttl: null,
                            record_type: "A",
                            line_index: null,
                            data: [],
                            is_new: true,
                            a_address: "",
                            from_domain_list: true,
                        };
                        ar.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ar.save = function() {
                            var submitRecord = [];
                            ar.resource.data.push(ar.resource.a_address);
                            submitRecord.push(ar.resource);
                            return Zones.saveRecords(ar.domain, submitRecord)
                                .then(function(results) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully added the following [asis,A] record for “[_1]”: [_2]", ar.domain, _.escape(ar.resource.dname)),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor",
                                    });
                                }, function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close({ $value: ar.resource });
                                });
                        };
                    };

                    list.aRecordModalController.$inject = ["$uibModalInstance", "domain"];

                    list.cnameRecordModalController = function($uibModalInstance, domain) {
                        var cr = this;
                        cr.domain = domain;
                        cr.modal_header = LOCALE.maketext("Add a [asis,CNAME] Record for “[_1]”", domain);
                        cr.name_label = list.modal.name_label;
                        cr.cname_label = list.modal.cname_label;
                        cr.submit_label = list.modal.create_cname_record;
                        cr.cancel_label = list.modal.cancel_label;
                        cr.required_msg = list.modal.required_msg;
                        cr.zone_name_placeholder = Zones.format_zone_name(domain, "example");

                        cr.resource = {
                            dname: "",
                            ttl: null,
                            record_type: "CNAME",
                            line_index: null,
                            data: [],
                            is_new: true,
                            cname: "",
                            from_domain_list: true,
                        };
                        cr.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        cr.save = function() {
                            var submitRecord = [];
                            cr.resource.data.push(cr.resource.cname);
                            submitRecord.push(cr.resource);

                            return Zones.saveRecords(cr.domain, submitRecord)
                                .then( function(results) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully added the following [asis,CNAME] record for “[_1]”: [_2]", cr.domain, _.escape(cr.resource.dname)),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor",
                                    });
                                }, function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close({ $value: cr.resource });
                                });
                        };
                    };

                    list.cnameRecordModalController.$inject = ["$uibModalInstance", "domain"];

                    list.mxRecordModalController = function($uibModalInstance, domain) {
                        var mxr = this;
                        mxr.domain = domain;
                        mxr.modal_header = LOCALE.maketext("Add an [asis,MX] Record for “[_1]”", domain);
                        mxr.name_label = list.modal.name_label;
                        mxr.exchanger_label = list.modal.exchanger_label;
                        mxr.exchanger_placeholder = list.modal.exchanger_placeholder;
                        mxr.priority_label = list.modal.priority_label;
                        mxr.priority_placeholder = list.modal.priority_placeholder;
                        mxr.submit_label = list.modal.create_mx_record;
                        mxr.cancel_label = list.modal.cancel_label;
                        mxr.required_msg = list.modal.required_msg;

                        mxr.resource = {
                            dname: mxr.domain,
                            ttl: null,
                            record_type: "MX",
                            line_index: null,
                            data: [],
                            is_new: true,
                            exchange: "",
                            priority: null,
                            from_domain_list: true,
                        };

                        mxr.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        mxr.save = function() {
                            var submitRecord = [];
                            mxr.resource.data.push(parseInt(mxr.resource.priority, 10));
                            mxr.resource.data.push(mxr.resource.exchange);
                            submitRecord.push(mxr.resource);
                            return Zones.saveRecords(mxr.domain, submitRecord)
                                .then( function(results) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully added the [asis,MX] record for “[_1]”.", mxr.domain),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor",
                                    });
                                }, function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close({ $value: mxr.resource });
                                });
                        };
                    };

                    list.mxRecordModalController.$inject = ["$uibModalInstance", "domain"];

                    list.create_a_record = function(domainObj) {
                        list.modal.instance = $uibModal.open({
                            templateUrl: "views/a_record_form.html",
                            controller: list.aRecordModalController,
                            controllerAs: "ar",
                            resolve: {
                                domain: function() {
                                    return domainObj.domain;
                                },
                            },
                        });
                    };

                    list.create_cname_record = function(domainObj) {
                        list.modal.instance = $uibModal.open({
                            templateUrl: "views/cname_record_form.html",
                            controller: list.cnameRecordModalController,
                            controllerAs: "cr",
                            resolve: {
                                domain: function() {
                                    return domainObj.domain;
                                },
                            },
                        });
                    };

                    list.create_mx_record = function(domainObj) {
                        list.modal.instance = $uibModal.open({
                            templateUrl: "views/mx_record_form.html",
                            controller: list.mxRecordModalController,
                            controllerAs: "mxr",
                            resolve: {
                                domain: function() {
                                    return domainObj.domain;
                                },
                            },
                        });
                    };

                    list.nameserverCheck = function(domains) {
                        if ($routeParams.nameserver) {
                            list.nameserverGrowl();
                            domains.forEach(function(domainObj) {
                                if (defaultInfo.domains.includes(domainObj.domain)) {
                                    list.domains.push(domainObj);
                                }
                            });
                        } else {
                            list.domains = domains;
                        }
                    };

                    list.nameserverGrowl = function() {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("To edit a domain’s nameserver, select Manage next to the appropriate domain."),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "zoneEditor",
                        });
                    };

                    function load(force) {
                        if (force === void 0) {
                            force = false;
                        }

                        list.ui.is_loading = true;
                        return Domains.fetch(force)
                            .then(function(data) {
                                list.nameserverCheck(data);
                                table.loadData(list.domains);
                                list.render();
                            })
                            .catch(function(err) {
                                list.loading_error = true;
                                list.loading_error_message = err;
                            })
                            .finally(function() {
                                list.ui.is_loading = false;
                            });
                    }

                    list.goToView = function(view, domain) {
                        viewNavigationApi.loadView("/" + view + "/", { domain: domain } );
                    };

                    list.init = function() {
                        load();
                    };

                    list.init();
                },
            ]);

        return {
            namespace: MODULE_NAMESPACE,
        };
    }
);

/* eslint-disable camelcase */
/*
# models/dmarc_record.js                         Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('shared/js/zone_editor/models/dmarc_record',["lodash"],
    function(_) {

        "use strict";

        var dmarc_regex = /^[vV]\s*=\s*DMARC1\s*;\s*[pP]\s*=/;
        var dmarc_uri_regex = /^[a-z][a-z0-9+.-]*:[^,!;]+(?:![0-9]+[kmgt]?)?$/i;
        var dmarc_uri_scrub = function(val) {

            /* If the value doesn't have a valid URI scheme and it looks
             * vaguely like an email, turn it into a mailto: URI.  The email
             * check is extremely open ended to allow for internationalized
             * emails, which may be used in mailto: URIs -- no punycode
             * required. */
            // TODO: convert domain to punycode for shorter storage (and better validation)
            if (!/^[a-z][a-z0-9+.-]*:/i.test(val) && /@[^\s@]{2,255}$/.test(val)) {

                /* See https://tools.ietf.org/html/rfc6068#section-2 */
                // eslint-disable-next-line no-useless-escape
                val = "mailto:" + encodeURI(val).replace(/[\/?#&;=]/g, function(c) {
                    return "%" + c.charCodeAt(0).toString(16);
                });
            }

            /* Additionally, DMARC requires [,!;] to be URI encoded, as they are
             * used specially by DMARC fields. */
            var invalidChars = /[,!;]/g;
            if (invalidChars.test(val)) {

                /* Strip off a valid file size suffix before munging */
                var size = "";
                val = val.replace(/![0-9]+[kmgt]?$/i, function(trail) {
                    size = trail;
                    return "";
                });

                val = val.replace(invalidChars, function(c) {
                    return "%" + c.charCodeAt(0).toString(16);
                });

                val += size;
            }
            return val;
        };

        /**
         * Checks if a variable is defined, null, and not an empty string
         *
         * @method is_defined_and_not_null
         */
        var is_defined_and_not_null = function(val) {
            return val !== void 0 && val !== null && ((typeof val === "string") ? val.length > 0 : true);
        };

        /**
         * Creates a DMARC Record object
         *
         * @class
         */
        function DMARCRecord() {
            this.resetProperties();
        }

        /**
         * Set (or reset) the object properties to defaults
         *
         * @method resetProperties
         */
        DMARCRecord.prototype.resetProperties = function() {
            this.p = "none";
            this.sp = "none";
            this.adkim = "r";
            this.aspf = "r";
            this.pct = 100;
            this.fo = "0";
            this.rf = "afrf";
            this.ri = 86400;
            this.rua = "";
            this.ruf = "";
        };

        DMARCRecord.prototype.validators = {
            p: {
                values: ["none", "quarantine", "reject"],
                defValue: "none"
            },
            sp: {
                values: ["none", "quarantine", "reject"],
            },
            adkim: {
                values: ["r", "s"],
                defValue: "r"
            },
            aspf: {
                values: ["r", "s"],
                defValue: "r"
            },
            rf: {
                multi: ":",
                values: ["afrf", "iodef"],
                defValue: "afrf",
            },
            fo: {
                multi: ":",
                values: ["0", "1", "s", "d"],
                defValue: "0"
            },
            pct: {
                pattern: /^[0-9]{1,2}$|^100$/,
                defValue: 100
            },
            ri: {
                pattern: /^\d+$/,
                defValue: 86400
            },
            rua: {
                multi: ",",
                scrub: dmarc_uri_scrub,
                pattern: dmarc_uri_regex,
                defValue: ""
            },
            ruf: {
                multi: ",",
                scrub: dmarc_uri_scrub,
                pattern: dmarc_uri_regex,
                defValue: ""
            }
        };

        /**
         * Check whether a text string represents a minimal
         * DMARC record
         *
         * @method isDMARC
         * @param {String} stringToTest
         */
        DMARCRecord.prototype.isDMARC = function(stringToTest) {
            return dmarc_regex.test(stringToTest);
        };

        var processValue = function(propValue, validationOpts, filter) {

            /* Split up multi-valued items (as applicable), and strip whitespace */
            var values = [ propValue ];
            if (validationOpts.multi) {
                values = propValue.split(validationOpts.multi).map(function(s) {
                    return s.trim();
                });
            }

            if (validationOpts.scrub) {
                values = values.map(validationOpts.scrub);
            }

            if (filter) {

                /* Define the appropriate test for finding valid entries */
                var test;
                if (validationOpts.pattern) {
                    test = function(val) {
                        return validationOpts.pattern.test(val.toLowerCase());
                    };
                } else if (validationOpts.values) {
                    test = function(val) {
                        return validationOpts.values.indexOf(val.toLowerCase()) > -1;
                    };
                }

                values = filter(values, test);
            }

            var cleanedValue = values.join(validationOpts.multi);
            return cleanedValue;
        };

        /**
         * Validate the value of a given property.
         *
         * @method isValid
         * @param {String} propName
         * @param {String} propValue
         */
        DMARCRecord.prototype.isValid = function(propName, propValue) {
            var isValid;

            /* Return true iff every value is valid */
            processValue(propValue, this.validators[propName], function(values, validator) {
                isValid = values.every(validator);
                return values;
            });

            return isValid;
        };

        /**
         * Validate and save the value of the given property.  Invalid values
         * are stripped from the property.  If no valid values remain, the
         * default value is saved.
         *
         * @method setValue
         * @param {String} propName
         * @param {String} propValue
         * @param {boolean} removeInvalid (optional)
         */
        DMARCRecord.prototype.setValue = function(propName, propValue, removeInvalid) {
            var filter;
            if (removeInvalid) {
                filter = function(values, validator) {
                    return values.filter(validator);
                };
            }

            var cleanedValue = processValue(propValue, this.validators[propName], filter);

            if (cleanedValue.length) {
                if (typeof this[propName] === "number") {
                    this[propName] = parseInt(cleanedValue, 10);
                } else {
                    this[propName] = cleanedValue;
                }
            } else if (propName === "sp") {
                this.sp = this.p;
            } else {
                this[propName] = this.validators[propName].defValue;
            }
        };

        /**
         * Populate the DMARC record properties from a TXT record
         *
         * @method fromTXT
         * @param {String} rawText - The text from a TXT DNS record
         */
        DMARCRecord.prototype.fromTXT = function(rawText) {
            this.resetProperties();

            if (_.isArray(rawText)) {

                // Multipart String Array (TXT Array)
                rawText = rawText.join(";");

            }

            if (typeof rawText === "string") {
                var properties = rawText.split(";");
                for (var i = 0; i < properties.length; i++) {
                    var keyValue = properties[i].split("=");
                    var propName = keyValue[0].trim().toLowerCase();
                    var propValue = keyValue.slice(1).join("=").trim();
                    if (propName !== "v" && this.hasOwnProperty(propName)) {
                        this.setValue(propName, propValue);
                    }
                }
            }
        };

        /**
         * Return a string version of the DMARC record suitable for saving
         * as a DNS TXT record
         *
         * @method toString
         * @return {String}
         */
        DMARCRecord.prototype.toString = function() {
            var generated_record = "v=DMARC1;p=" + this.p;
            if (is_defined_and_not_null(this.sp)) {
                generated_record += ";sp=" + this.sp;
            }
            if (is_defined_and_not_null(this.adkim)) {
                generated_record += ";adkim=" + this.adkim;
            }
            if (is_defined_and_not_null(this.aspf)) {
                generated_record += ";aspf=" + this.aspf;
            }
            if (is_defined_and_not_null(this.pct)) {
                generated_record += ";pct=" + this.pct;
            }
            if (is_defined_and_not_null(this.fo)) {
                generated_record += ";fo=" + this.fo;
            }
            if (is_defined_and_not_null(this.rf)) {
                generated_record += ";rf=" + this.rf;
            }
            if (is_defined_and_not_null(this.ri)) {
                generated_record += ";ri=" + this.ri;
            }
            if (is_defined_and_not_null(this.rua)) {

                // fix mailto uri list if necessary
                this.setValue("rua", this.rua);
                generated_record += ";rua=" + this.rua;
            }
            if (is_defined_and_not_null(this.ruf)) {

                // fix mailto uri list if necessary
                this.setValue("ruf", this.ruf);
                generated_record += ";ruf=" + this.ruf;
            }
            return generated_record;
        };

        return DMARCRecord;
    }
);

/*
# cpanel - base/sharedjs/zone_editor/utils/dnssec.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( 'shared/js/zone_editor/utils/dnssec',[
    "lodash",
], function(_) {
    "use strict";

    var dsAlgorithms = [
        {
            "algorithmId": 1,
            "algorithm": "1-RSAMD5",
        },
        {
            "algorithmId": 2,
            "algorithm": "2-Diffie-Hellman",
        },
        {
            "algorithmId": 3,
            "algorithm": "3-DSA/SHA-1",
        },
        {
            "algorithmId": 4,
            "algorithm": "4-Elliptic Curve",
        },
        {
            "algorithmId": 5,
            "algorithm": "5-RSA/SHA-1",
        },
        {
            "algorithmId": 7,
            "algorithm": "7-RSASHA1-NSEC3-SHA1",
        },
        {
            "algorithmId": 8,
            "algorithm": "8-RSA/SHA-256",
        },
        {
            "algorithmId": 10,
            "algorithm": "10-RSA/SHA-512",
        },
        {
            "algorithmId": 13,
            "algorithm": "13-ECDSA Curve P-256 with SHA-256",
        },
        {
            "algorithmId": 14,
            "algorithm": "14-ECDSA Curve P-384 with SHA-384",
        },
        {
            "algorithmId": 252,
            "algorithm": "252-Indirect",
        },
        {
            "algorithmId": 253,
            "algorithm": "253-Private DNS",
        },
        {
            "algorithmId": 254,
            "algorithm": "254-Private OID",
        },
    ];

    var dsDigTypes = [
        {
            "digTypeId": 1,
            "digType": "1-SHA-1",
        },
        {
            "digTypeId": 2,
            "digType": "2-SHA-256",
        },
        {
            "digTypeId": 4,
            "digType": "4-SHA-384",
        },
    ];

    return {
        dsAlgorithms: dsAlgorithms,
        dsDigTypes: dsDigTypes,
    };
});

/*
# cpanel - base/sharedjs/zone_editor/utils/recordData.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( 'shared/js/zone_editor/utils/recordData',[
    "lodash",
    "shared/js/zone_editor/utils/dnssec",
], function(_, DNSSEC) {
    "use strict";

    // Keys are record types; values are arrays of 2-member arrays;
    // each 2-member array is the record-object key and its default.
    //
    // Note the following “special” defaults:
    //  - If the default is a function, the function’s result will be
    //      the default.
    //  - If the default is undefined, the key will be omitted from
    //      the default data.
    //
    var TYPE_FIELDS_WITH_DEFAULTS = {
        A: [
            { key: "a_address", default: "" },
        ],

        AAAA: [
            { key: "aaaa_address", default: "" },
        ],

        AFSDB: [
            { key: "subtype", default: null },
            { key: "hostname", default: "" },
        ],

        CAA: [
            { key: "flag", default: 0 },
            { key: "tag", default: "issue" },
            { key: "value", default: "" },
        ],

        CNAME: [
            { key: "cname", default: "" },
        ],

        DNAME: [
            { key: "dname", default: "" },
        ],

        DS: [
            { key: "keytag", default: "" },
            { key: "algorithm", default: DNSSEC.dsAlgorithms[0].algorithm },
            { key: "digtype", default: DNSSEC.dsDigTypes[0].digType },
            { key: "digest", default: "" },
        ],

        HINFO: [
            { key: "cpu", default: "" },
            { key: "os", default: "" },
        ],

        LOC: [
            { key: "latitude", default: "" },
            { key: "longitude", default: "" },
            { key: "altitude", default: null },
            { key: "size", default: "1" },
            { key: "horiz_pre", default: "1000" },
            { key: "vert_pre", default: "10" },
        ],

        MX: [
            { key: "priority", default: null },
            { key: "exchange", default: undefined },
        ],

        NS: [
            { key: "nsdname", default: "" },
        ],

        NAPTR: [
            { key: "order", default: null },
            { key: "preference", default: null },
            { key: "flags", default: null },
            { key: "service", default: "" },
            { key: "regexp", default: "" },
            { key: "replacement", default: "" },
        ],

        PTR: [
            { key: "ptrdname", default: "" },
        ],

        RP: [
            { key: "mbox", default: "" },
            { key: "txtdname", default: "" },
        ],

        SOA: [
            { key: "serial", default: "" },
            { key: "mname", default: "" },
            { key: "retry", default: null },
            { key: "refresh", default: null },
            { key: "expire", default: null },
            { key: "rname", default: "" },
        ],

        SRV: [
            { key: "priority", default: null },
            { key: "weight", default: null },
            { key: "port", default: null },
            { key: "target", default: "" },
        ],

        TXT: [
            { key: "txtdata", default: function() {
                return [];
            } },
        ],
    };

    function createNewDefaultData() {
        var data = {};

        Object.values(TYPE_FIELDS_WITH_DEFAULTS).forEach( function(fields) {
            fields.forEach( function(field) {
                var rawValue = field.default;

                var realValue;

                if (typeof rawValue === "function") {
                    realValue = rawValue();
                } else if (typeof rawValue === "undefined") {
                    return;
                } else {
                    realValue = rawValue;
                }

                data[ field.key ] = realValue;
            } );
        } );

        return data;
    }

    var TYPE_SEARCH = {};

    Object.keys(TYPE_FIELDS_WITH_DEFAULTS).forEach( function(type) {
        var keys = TYPE_FIELDS_WITH_DEFAULTS[type].map(
            function(keyValue) {
                return keyValue.key;
            }
        );

        var keysCount = keys.length;

        TYPE_SEARCH[type] = function(record, sought) {
            for (var k = 0; k < keysCount; k++) {
                var fieldValue = record[ keys[k] ];

                if (fieldValue === null || fieldValue === undefined) {
                    continue;
                }

                if (-1 !== fieldValue.toString().indexOf(sought)) {
                    return true;
                }
            }

            return false;
        };
    } );

    // A special snowflake:
    TYPE_SEARCH.TXT = function(record, sought) {

        // Each TXT record is an array of strings. While not all protocols
        // define a join mechanism for those strings, it’s commonplace to
        // concatenate them together. (e.g., DKIM and SPF) Since this is
        // both common and also kind of a “default”, simplest model,
        // let’s apply it here.
        //
        var txtdata = record.txtdata.join("");

        if (-1 !== txtdata.indexOf(sought)) {
            return true;
        }

        return false;
    };

    return {
        createNewDefaultData: createNewDefaultData,
        searchByType: TYPE_SEARCH,
    };
});

/*
# cpanel - base/sharedjs/zone_editor/utils/recordSet.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( 'shared/js/zone_editor/utils/recordSet',[
    "lodash",
], function(_) {
    "use strict";

    // cf. DNS_RDATATYPEATTR_SINGLETON in bind9.
    var IS_SINGLETON_TYPE = {
        CNAME: true,

        // DNAME and SOA are also singleton types, but
        // we don’t handle DNAME, and this interface doesn’t
        // expose controls to create additional SOAs.
    };

    function RecordSet() {
        this.records = [];
    }
    Object.assign(
        RecordSet.prototype,
        {
            _ttlsAllMatch: true,

            _ttl: null,

            add: function add(record) {
                record.ttl = parseInt(record.ttl, 10);

                this.records.push(record);

                if (this._ttl) {
                    this._ttlsAllMatch = (this._ttl === record.ttl);
                } else {
                    this._ttl = record.ttl;
                }
            },

            ttlsMismatch: function ttlsMismatch() {
                return !this._ttlsAllMatch;
            },

            singletonExcess: function singletonExcess() {
                return IS_SINGLETON_TYPE[this.records[0].record_type] ? this.records.length > 1 : false;
            },

            ttls: function ttls() {
                return _.uniq(
                    this.records.map(
                        function(r) {
                            return r.ttl;
                        }
                    )
                );
            },

            count: function count() {
                return this.records.length;
            },

            name: function name() {
                return this.records[0].name;
            },

            type: function type() {
                return this.records[0].record_type;
            },
        }
    );

    return RecordSet;
});

/*
# cpanel - base/sharedjs/zone_editor/utils/recordSetIndex.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( 'shared/js/zone_editor/utils/recordSetIndex',[
    "shared/js/zone_editor/utils/recordSet",
], function(RecordSet) {
    "use strict";

    function RecordSetIndex() {}
    Object.assign(
        RecordSetIndex.prototype,
        {
            query: function query(name, type) {
                var key = name + ":" + type;

                if (!this[key]) {
                    this[key] = new RecordSet();
                }

                return this[key];
            },

            sets: function sets() {
                return Object.values(this);
            },
        }
    );

    return RecordSetIndex;
});

/*
# cpanel - base/sharedjs/zone_editor/directives/base_validators.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('shared/js/zone_editor/directives/base_validators',[
    "angular",
    "cjt/validator/length-validators",
],
function(angular, lengthValidators) {
    "use strict";

    var MAX_CHAR_STRING_BYTE_LENGTH = 255;

    var validators = {
        characterStringValidator: function(val) {
            return lengthValidators.methods.maxUTF8Length(val, MAX_CHAR_STRING_BYTE_LENGTH);
        },
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        },
    ]);

    return {
        methods: validators,
        name: "baseValidators",
        description: "General DNS record validation library",
        version: 1.0,
    };
});

/*
# directives/dmarc_validators.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

define('shared/js/zone_editor/directives/dmarc_validators',[
    "angular",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "shared/js/zone_editor/models/dmarc_record",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, LOCALE, validationUtils, DMARCRecord) {

    "use strict";

    // eslint-disable-next-line camelcase
    var dmarc_record = new DMARCRecord();

    /**
         * Validate dmarc record mailto list
         *
         * @method  dmarcMailtoList
         * @param {string} mailto uri list
         * @param {string} list to validate (rua | ruf)
         * @return {object} validation result
         */
    var validators = {
        dmarcMailtoList: function(val, prop) {
            var result = validationUtils.initializeValidationResult();

            result.isValid = dmarc_record.isValid(prop, val);
            if (!result.isValid) {
                result.add("dmarcMailtoList", LOCALE.maketext("The [asis,URI] list is invalid."));
            }
            return result;
        }
    };

        // Generate a directive for each validation function
    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "dmarcValidators",
        description: "Validation library for DMARC records.",
        version: 2.0,
    };
});

/*
# directives/caa_validators.js                            Copyright(c) 2020 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-disable camelcase */
/* global define: false */

define('shared/js/zone_editor/directives/caa_validators',[
    "angular",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/domain-validators",
    "cjt/validator/email-validator",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, LOCALE, validationUtils, DOMAIN_VALIDATORS, EMAIL_VALIDATORS) {

    "use strict";

    var mailToRegex = /^mailto:/;

    /**
     * Validate caa record iodef variant of value field
     *
     * @method  validate_iodef
     * @param {string} iodef value
     * @return {object} validation result
     */

    var validate_iodef = function(val) {
        var result = validationUtils.initializeValidationResult();
        var otherResult;

        // can be a mailto URL or a standard URL (possibly for some sort of web service)

        result.isValid = false;

        if (mailToRegex.test(val)) {
            val = val.replace(mailToRegex, "");
            otherResult = EMAIL_VALIDATORS.methods.email(val);
        } else {
            otherResult = DOMAIN_VALIDATORS.methods.url(val);
        }

        result.isValid = otherResult.isValid;

        if (!result.isValid) {
            result.add("caaIodef", LOCALE.maketext("You must enter a valid [asis,mailto] or standard [asis,URL]."));
        }

        return result;
    };

    /**
     * Validate caa record issue or issuewild variant of value field
     *
     * @method  validate_issue
     * @param {string} issue/issuewild value
     * @return {object} validation result
     */

    var validate_issue = function(val) {
        var result = validationUtils.initializeValidationResult();

        // should be a valid zone name without optional parameters specified by the issuer.
        // the dns servers we support do not allow additional parameters after the semicolon.

        result.isValid = false;

        if (val === ";") {

            // ";" is a valid issue/issuewild value which disallows any
            // certificates

            result.isValid = true;
        } else {

            var zoneNameResult = DOMAIN_VALIDATORS.methods.zoneFqdn(val);
            result.isValid = zoneNameResult.isValid;
        }

        if (!result.isValid) {
            result.add("caaIssue", LOCALE.maketext("You must enter a valid zone name or a single semicolon."));
        }

        return result;
    };

    var validators = {

        caaValue: function(val, type) {
            if (type === "iodef") {
                return validate_iodef(val);
            } else {
                return validate_issue(val);
            }
        }
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "caaValidators",
        description: "Validation library for CAA records.",
        version: 1.0
    };
});

/*
# directives/ds_validators.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('shared/js/zone_editor/directives/ds_validators',[
    "angular",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, LOCALE, validationUtils) {

    "use strict";

    var digestRegex = /^[0-9a-f\s]+$/i;

    var validateDigestRegex = function(val, regex) {
        var result = validationUtils.initializeValidationResult();

        result.isValid = regex.test(val);

        if (!result.isValid) {
            result.add("digest", LOCALE.maketext("The ‘Digest‘ must be represented by a sequence of case-insensitive hexadecimal digits. Whitespace is allowed."));
        }

        return result;
    };

    var validators = {
        digestValidator: function(val) {
            return validateDigestRegex(val, digestRegex);
        }
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "digestValidators",
        description: "Validation library for DS records.",
        version: 2.0,
    };
});

/*
# directives/naptr_validators.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('shared/js/zone_editor/directives/naptr_validators',[
    "angular",
    "lodash",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory",
],
function(angular, _, LOCALE, validationUtils) {

    "use strict";

    var validateServiceRegex = function(serviceValue) {
        var result = validationUtils.initializeValidationResult();

        /**
             * According to RFC - https://tools.ietf.org/html/rfc2915#section-2
             * The service field may take any of the values below(using the
             * Augmented BNF of RFC 2234[5]):
             *  service_field = [[protocol] * ("+" rs)]
             *      protocol = ALPHA * 31ALPHANUM
             *      rs = ALPHA * 31ALPHANUM
             *      ; The protocol and rs fields are limited to 32
             *      ; characters and must start with an alphabetic.
             *
             * Of note: RFC 3403 is the current specification, and it
             * does not define the above validation logic.
            **/
        // Empty value is a valid value.
        if (serviceValue === "") {
            result.isValid = true;
            return result;
        }

        var values = serviceValue.split("+");
        var protocol, rsValues;
        if (values.length > 0) {
            protocol = values.shift();
            rsValues = (values.length > 0) ? values : null;
        }

        if (!/^[a-z]/i.test(protocol)) {
            result.isValid = false;
            result.add("naptrservice", LOCALE.maketext("Service must start with a letter."));
            return result;
        }

        if (!/^[a-z][:a-z0-9\-+]{0,31}$/i.test(protocol)) {
            result.isValid = false;
            result.add("naptrservice", LOCALE.maketext("“Protocol”, the first part of the service field must contain only case insensitive letters a-z, digits 0-9, ‘-’s and ‘+’s. It must not exceed 32 characters."));
            return result;
        }

        if (rsValues) {

            var invalidRsValue = _.some(rsValues, function(rs) {
                if (rs !== "") {
                    return !(/^[:a-z0-9\-+]{1,32}$/i.test(rs));
                }
            });
            if (invalidRsValue) {
                result.isValid = false;
                result.add("naptrservice", LOCALE.maketext("Each “rs” value (the value after ‘+’ symbols) must contain only case insensitive letters a-z, digits 0-9, ‘-’s and ‘+’s. It must not exceed 32 characters."));
                result;
            }
        }

        return result;
    };

    var validateNaptrRegexField = function(naptrRegexVal) {
        var result = validationUtils.initializeValidationResult();
        if (naptrRegexVal === "") {
            return result;
        }

        // For validating the NAPTR record's ‘Regexp’ field, we used the RFC as a reference:
        // https://tools.ietf.org/html/rfc2915#page-7
        var delimCharPattern = "[^0-9i]";
        var delimCharRegex = new RegExp(delimCharPattern);
        var delimChar = naptrRegexVal.charAt(0);

        if (!delimCharRegex.test(delimChar)) {
            result.isValid = false;
            result.add("naptrRegex", LOCALE.maketext("You can not use a digit or the flag character ‘i’ as your delimiter."));
            return result;
        }

        var delimOccurrenceRegex = new RegExp("^(" + delimCharPattern + ").*\\1(.*)\\1.*");
        var matches = naptrRegexVal.match(delimOccurrenceRegex);
        if (matches === null) {
            result.isValid = false;
            result.add("naptrRegex", LOCALE.maketext("To separate regular and replacement expressions, you must enter the delimiter before, between, and after the expressions. For example, delim-char regex delim-char replacement delim-char."));
            return result;
        }
        return result;
    };

    var validators = {
        serviceValidator: function(val) {
            return validateServiceRegex(val);
        },
        naptrRegexValidator: function(val) {
            return validateNaptrRegexField(val);
        },
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        },
    ]);

    return {
        methods: validators,
        name: "naptrValidators",
        description: "Validation library for NAPTR records.",
        version: 2.0,
    };
});

/* eslint-disable camelcase */
/*
# cpanel - base/sharedjs/zone_editor/views/manage.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* define: false */

/* jshint -W100 */

define(
    'shared/js/zone_editor/views/manage',[
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "shared/js/zone_editor/models/dynamic_table",
        "shared/js/zone_editor/models/dmarc_record",
        "shared/js/zone_editor/utils/dnssec",
        "shared/js/zone_editor/utils/recordData",
        "shared/js/zone_editor/utils/recordSetIndex",
        "app/services/features",
        "app/services/recordTypes",
        "uiBootstrap",
        "cjt/directives/multiFieldEditor",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeButtonDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/filters/qaSafeIDFilter",
        "cjt/validator/ip-validators",
        "cjt/validator/domain-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/datatype-validators",
        "cjt/validator/email-validator",
        "cjt/services/viewNavigationApi",
        "cjt/services/cpanel/nvDataService",
        "cjt/directives/quickFiltersDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "shared/js/zone_editor/directives/convert_to_full_record_name",
        "shared/js/zone_editor/directives/base_validators",
        "shared/js/zone_editor/directives/dmarc_validators",
        "shared/js/zone_editor/directives/caa_validators",
        "shared/js/zone_editor/directives/ds_validators",
        "shared/js/zone_editor/directives/naptr_validators",
    ],
    function(angular, _, CJT, LOCALE, DynamicTable, DMARCRecord, DNSSEC, RecordData, RecordSetIndex, FeaturesService, RecordTypesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.manage";
        var app = angular.module(MODULE_NAMESPACE, []);

        var _RECORD_SET_ERR_ALERT_ID = "record-set-error";
        var _ALERT_GROUP = "zoneEditor";

        function _getRecordSetErrors(records) {
            var set;

            var index = new RecordSetIndex();

            for (var r = 0; r < records.length; r++) {
                var record = records[r];
                set = index.query(record.name, record.record_type);
                set.add(record);
            }

            var phrases = [];

            var sets = index.sets();
            for (var s = 0; s < sets.length; s++) {
                set = sets[s];

                if (set.ttlsMismatch()) {
                    var name = set.name().replace(/\.$/, "");

                    phrases.push( LOCALE.maketext("[_1]’s “[_2]” [numerate,_3,,records have] mismatched [asis,TTL] [numerate,_3,,values] ([list_and,_4]). Records of the same name and type must always have the same [asis,TTL] value.", name, set.type(), set.count(), set.ttls()) );
                }

                if (set.singletonExcess()) {
                    phrases.push( LOCALE.maketext("Only 1 “[_1]” record may exist per name. Rename or delete [_2]’s extra “[_1]” [numerate,_3,record,records].", set.type(), set.name(), set.count() - 1) );
                }
            }

            return phrases;
        }

        app.controller(
            "ManageZoneRecordsController", [
                "$scope",
                "$location",
                "$routeParams",
                "$timeout",
                "Zones",
                "viewNavigationApi",
                "$uibModal",
                FeaturesService.serviceName,
                RecordTypesService.serviceName,
                "defaultInfo",
                "nvDataService",
                "alertService",
                function(
                    $scope,
                    $location,
                    $routeParams,
                    $timeout,
                    Zones,
                    viewNavigationApi,
                    $uibModal,
                    Features,
                    $recordTypes,
                    defaultInfo,
                    nvDataService,
                    alertService) {
                    var manage = this;

                    manage.is_loading = false;
                    manage.zone_records = [];
                    manage.domain = $routeParams.domain;
                    manage.loading_error = false;
                    manage.loading_error_message = "";
                    manage.Features = Features;
                    manage.generated_domains = {};
                    manage.recordTypes = [];
                    manage.types = [];
                    manage.recordsInProgress = [];
                    manage.serial = null;
                    manage.isHostnameZone = PAGE.serverHostname === manage.domain;
                    manage.showEmailRoutingLink = PAGE.showEmailRoutingLink ? true : false;

                    manage.dsAlgorithms = DNSSEC.dsAlgorithms;

                    manage.dsDigTypes = DNSSEC.dsDigTypes;

                    manage.save_in_progress = false;

                    function Record(record, new_dmarc) {

                        // creating a new DMARC record
                        if (record && record.record_type === "DMARC" ) {
                            record.name = Zones.format_zone_name(manage.domain, "_dmarc.");
                            record.is_dmarc = true;
                            record.record_type = "TXT";

                        // loading existing DMARC record
                        } else if (record && record.txtdata) {
                            record.is_dmarc = new_dmarc.isDMARC(record.txtdata[0]);
                        } else {
                            record.is_dmarc = false;
                        }

                        var newRecord = Object.assign(
                            RecordData.createNewDefaultData(),
                            {
                                _id: "",
                                name: record.name || "",
                                record_type: record.record_type,
                                editing: record.is_new === "1",
                                is_new: record.is_new,
                                viewTemplate: manage.viewRecordTemplates(record.record_type),
                                editTemplate: manage.getRecordTemplate(record),
                                ttl: record.ttl || manage.default_ttl,
                                line_index: null,

                                is_dmarc: record.is_dmarc,
                                p: "",
                                sp: "",
                                adkim: "",
                                aspf: "",
                                pct: "",
                                fo: "",
                                rf: "",
                                ri: "",
                                rua: "",
                                ruf: "",
                                record: "",
                            }
                        );

                        if (record.is_new === "0") {
                            switch (record.record_type) {
                                case "A":
                                    newRecord.a_address = Zones.trimTrailingDot(record.record) || "";
                                    newRecord.record = Zones.trimTrailingDot(record.record) || "";
                                    break;
                                case "AAAA":
                                    newRecord.aaaa_address = Zones.trimTrailingDot(record.record);
                                    newRecord.record = Zones.trimTrailingDot(record.record);
                                    break;
                                case "AFSDB":
                                    newRecord.subtype = record.subtype;
                                    newRecord.hostname = record.hostname;
                                    break;
                                case "CAA":
                                    newRecord.flag = record.flag;
                                    newRecord.tag = record.tag;
                                    newRecord.value = record.value;
                                    break;
                                case "CNAME":
                                    newRecord.cname = Zones.trimTrailingDot(record.record);
                                    newRecord.record = Zones.trimTrailingDot(record.record);
                                    break;
                                case "DNAME":
                                    newRecord.dname = Zones.trimTrailingDot(record.record);
                                    newRecord.record = Zones.trimTrailingDot(record.record);
                                    break;
                                case "DS":
                                    newRecord.keytag = record.keytag;
                                    newRecord.algorithm = getDSAlgorithmById(parseInt(record.algorithm, 10));
                                    newRecord.digtype = getDSDigestTypeId(parseInt(record.digtype, 10));
                                    newRecord.digest = record.digest;
                                    break;
                                case "HINFO":
                                    newRecord.cpu = record.cpu;
                                    newRecord.os = record.os;
                                    break;
                                case "LOC":
                                    newRecord.latitude = record.latitude.trim();
                                    newRecord.longitude = record.longitude.trim();
                                    newRecord.altitude = record.altitude;
                                    newRecord.size = record.size;
                                    newRecord.horiz_pre = record.horiz_pre;
                                    newRecord.vert_pre = record.vert_pre;
                                    break;
                                case "MX":
                                    newRecord.priority = record.priority;
                                    newRecord.exchange = record.exchange;
                                    break;
                                case "NS":
                                    newRecord.nsdname = Zones.trimTrailingDot(record.record);
                                    newRecord.record = Zones.trimTrailingDot(record.record);
                                    break;
                                case "NAPTR":
                                    newRecord.order = parseInt(record.order, 10);
                                    newRecord.preference = parseInt(record.preference, 10);
                                    newRecord.flags = record.flags;
                                    newRecord.service = record.service;
                                    newRecord.regexp = record.regexp;
                                    newRecord.replacement = record.replacement;
                                    break;
                                case "PTR":
                                    newRecord.ptrdname = Zones.trimTrailingDot(record.record);
                                    newRecord.record = Zones.trimTrailingDot(record.record);
                                    break;
                                case "RP":
                                    newRecord.mbox = record.mbox;
                                    newRecord.txtdname = record.txtdname;
                                    break;
                                case "SRV":
                                    newRecord.priority = parseInt(record.priority, 10);
                                    newRecord.weight = parseInt(record.weight, 10);
                                    newRecord.port = parseInt(record.port, 10);
                                    newRecord.target = record.target;
                                    break;
                                case "SOA":
                                    newRecord.serial = record.serial;
                                    newRecord.mname = record.mname;
                                    newRecord.retry = parseInt(record.retry, 10);
                                    newRecord.refresh = parseInt(record.refresh, 10);
                                    newRecord.expire = parseInt(record.expire, 10);
                                    newRecord.rname = record.rname;
                                    break;
                                case "TXT":
                                    newRecord.txtdata = record.txtdata;

                                    if (record.is_dmarc) {
                                        new_dmarc.fromTXT(newRecord.txtdata[0]);
                                    }
                                    break;
                            }
                            newRecord.line_index = record.line_index;
                        }

                        newRecord.id_prefix = newRecord.record_type.toLowerCase();

                        newRecord.cache = angular.copy(newRecord);

                        newRecord.typeEditingLocked = newRecord.record_type === "SOA" || newRecord.is_dmarc;

                        newRecord.getSetRName = manage.getSetRName.bind(this, "rname");
                        newRecord.getSetMBOX = manage.getSetRName.bind(this, "mbox");

                        Object.assign(
                            this,
                            newRecord,
                            new_dmarc,
                            DMARCRecord.prototype
                        );
                    }

                    manage.getSetRName = function getSetRName(property, newValue) {
                        if (angular.isDefined(newValue)) {
                            this[property] = manage.convertEmailToRName(newValue);
                        }
                        return manage.convertRNameToEmail(this[property]);
                    };

                    manage.convertRNameToEmail = function(rName) {
                        var email = rName;

                        // Separate the parts at escaped dots
                        // We will reassemble below
                        email = email.split(/\\\./g);

                        // Find the first unescaped dot and convert it
                        for (var i = 0; i < email.length; i++) {
                            if (email[i].indexOf(".") !== -1) {
                                email[i] = email[i].replace(".", "@");
                                break;
                            }
                        }

                        // Reassemble with unescaped dots
                        email = email.join(".");
                        return email;
                    };
                    manage.convertEmailToRName = function(email) {
                        var rName = email;

                        // Split the email at the "@"
                        rName = rName.split("@");

                        // Escape dots before the "@"
                        rName[0] = rName[0].replace(/\./g, "\\.");

                        // Reassemble the parts with a dot
                        rName = rName.join(".");

                        return rName;
                    };

                    manage.selectDMARCTab = function(zone_rec, tab) {
                        if (tab === "RAW") {
                            zone_rec.rawTabSelected = true;
                            manage.updateTXTFromDMARCRecord(zone_rec);
                        } else {
                            manage.updateDMARCRecordFromTXT(zone_rec);
                            zone_rec.rawTabSelected = false;
                        }
                    };

                    manage.updateDMARCRecordFromTXT = function(record) {
                        record.fromTXT(record.txtdata);
                    };

                    manage.updateTXTFromDMARCRecord = function(record) {
                        record.txtdata = record.toString();
                    };

                    manage.isActionBtnVisible = function() {
                        return Features.whmOnly || Features.advanced;
                    };

                    manage.isFormEditing = function() {
                        var record;
                        for (var i = 0, len = manage.filteredList.length; i < len; i++) {
                            record = manage.filteredList[i];
                            if (record.editing) {
                                return true;
                            }
                        }
                        return false;
                    };

                    manage.viewRawZone = function viewRawZone() {
                        viewNavigationApi.loadView("/manage/copyzone", { domain: this.domain } );
                    };

                    var table = new DynamicTable();

                    function searchByNameOrData(item, searchText) {

                        if (item.name) {
                            if (item.name.indexOf(searchText) !== -1) {
                                return true;
                            }
                        } else if (item.is_new === "1") {
                            return true;
                        }

                        return RecordData.searchByType[item.record_type](item, searchText);
                    }

                    function searchByType(item, type) {
                        return item.record_type === type || item.is_new === "1";
                    }

                    function filterListFilter() {

                        // Return if manage.types already exist.
                        if (manage.types && manage.types.length > 0) {
                            return;
                        }

                        var types = _.sortBy(_.uniq(_.map(manage.zone_records, function(record) {
                            return record.record_type;
                        })));
                        manage.types = _.filter(types, function(type) {
                            return manage._featureAllowed(type);
                        });
                        revertToAllFilter();
                    }

                    function updateFilterListFilter(record, action) {
                        var typeGiven = record.record_type;
                        if (action === "add") {
                            if (!_.includes(manage.types, typeGiven)) {
                                manage.types = _.sortBy(_.concat(manage.types, typeGiven));
                            }
                        } else if (action === "remove") {

                            // Check if there exist any other records of the same type as the record which we removed.
                            // If not, then remove the type from manage.types.
                            var recordsOfGivenType = _.filter(manage.zone_records, function(recItem) {
                                if (recItem._id !== record._id && recItem.record_type === typeGiven) {
                                    return record;
                                }
                            });
                            if (recordsOfGivenType.length === 0) {
                                manage.types = _.sortBy(_.pull(manage.types, typeGiven));
                            }
                        }
                        revertToAllFilter();
                    }

                    function revertToAllFilter() {
                        if (!(manage.types.includes(manage.meta.quickFilterValue))) {
                            manage.meta.quickFilterValue = "";
                        }
                    }

                    function getDSAlgorithmById(id) {
                        var algorithmObj =  _.find(manage.dsAlgorithms, ["algorithmId", parseInt(id)]);
                        return (algorithmObj) ? algorithmObj.algorithm : "";
                    }

                    function getDSAlgorithmByAlgo(algo) {
                        var algorithmObj = _.find(manage.dsAlgorithms, ["algorithm", algo]);
                        return algorithmObj.algorithmId;
                    }

                    function getDSDigestTypeId(id) {
                        var digestObj = _.find(manage.dsDigTypes, ["digTypeId", parseInt(id)]);
                        return (digestObj) ? digestObj.digType : "";
                    }

                    function getDSDigestTypeAlgo(algo) {
                        var digestObj = _.find(manage.dsDigTypes, ["digType", algo]);
                        return digestObj.digTypeId;
                    }


                    table.setFilterFunction(searchByNameOrData);
                    table.setQuickFilterFunction(searchByType);
                    table.meta.pageSize = defaultInfo.zones_per_page;

                    manage.meta = table.getMetadata();
                    manage.filteredList = table.getList();
                    manage.paginationMessage = table.paginationMessage;

                    manage.checkRecordSets = function() {
                        var errs = _getRecordSetErrors(this.zone_records);

                        if (errs.length) {
                            var html = errs.map( function(m) {

                                // It’s unideal to mess with HTML in a
                                // controller but more or less necessary
                                // since alertService requires HTML.
                                return "<p>" + m + "</p>";
                            } ).join("");

                            alertService.add({
                                type: "danger",
                                id: _RECORD_SET_ERR_ALERT_ID,
                                message: html,
                                closeable: true,
                                replace: true,
                                group: _ALERT_GROUP,
                            });
                        } else {
                            alertService.removeById(_RECORD_SET_ERR_ALERT_ID, _ALERT_GROUP);
                            return true;
                        }

                        return false;
                    };

                    manage.render = function() {
                        manage.filteredList = table.populate();
                    };
                    manage.sortList = function() {
                        manage.render();
                    };
                    manage.selectPage = function() {
                        manage.render();
                    };
                    manage.selectPageSize = function() {
                        manage.render();
                        if (defaultInfo.zones_per_page !== table.meta.pageSize) {
                            nvDataService.setObject(
                                {
                                    zones_per_page: table.meta.pageSize,
                                })
                                .then(function() {
                                    defaultInfo.zones_per_page = table.meta.pageSize;
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                });
                        }
                    };
                    manage.searchList = function() {
                        manage.getFilteredResults();
                    };

                    manage.getFilteredResults = function() {
                        manage.filteredList = table.populate();
                    };

                    manage.dynamicPlaceholders = {
                        issue: LOCALE.maketext("Certificate Authority"),
                        iodef: LOCALE.maketext("Mail Address for Notifications"),
                    };

                    manage.dynamicTooltips = {
                        issue: LOCALE.maketext("The certificate authority’s domain name."),
                        iodef: LOCALE.maketext("The location to which the certificate authority will report exceptions. Either a [asis,mailto] or standard [asis,URL]."),
                    };

                    manage.valueTooltip = function(idx) {
                        if (manage.filteredList[idx].tag === "iodef") {
                            return manage.dynamicTooltips.iodef;
                        }

                        return manage.dynamicTooltips.issue;
                    };

                    manage.valuePlaceholder = function(idx) {
                        if (manage.filteredList[idx].tag === "iodef") {
                            return manage.dynamicPlaceholders.iodef;
                        }

                        return manage.dynamicPlaceholders.issue;
                    };

                    function RemoveRecordModalController($uibModalInstance, record) {
                        var ctrl = this;
                        ctrl.record = record;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            var lineIdx = [record.line_index];
                            return Zones.remove_zone_record(manage.domain, lineIdx, manage.serial)
                                .then(function() {
                                    if (record.record_type === "MX" && record.name === manage.domain + ".") {
                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("You successfully deleted the [_1] record.", _.escape(record.record_type)),
                                            closeable: true,
                                            replace: false,
                                            autoClose: 10000,
                                            group: "zoneEditor",
                                        });
                                    } else {
                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("You successfully deleted the [_1] record: [_2]", record.record_type, _.escape(record.name)),
                                            closeable: true,
                                            replace: false,
                                            autoClose: 10000,
                                            group: "zoneEditor",
                                        });
                                    }
                                    updateFilterListFilter(record, "remove");
                                    manage.refresh();
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }

                    RemoveRecordModalController.$inject = [ "$uibModalInstance", "record" ];

                    function ResetZoneModalController($uibModalInstance) {
                        var ctrl = this;
                        manage.recordsInProgress = [];

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return Zones.reset_zone(manage.domain)
                                .then(function() {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully reset the zone for “[_1]”.", _.escape(manage.domain)),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor",
                                    });
                                    manage.refresh();
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor",
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }

                    ResetZoneModalController.$inject = [ "$uibModalInstance" ];

                    manage.emailRoutingConfigLink = function() {
                        var link;
                        if (Features.whmOnly) {
                            link = CJT.protocol + "//" + CJT.domain + ":" + CJT.port + CJT.securityToken + "/scripts/doeditmx?domainselect=" + manage.domain;
                        } else {
                            link = location.origin + PAGE.securityToken + "/frontend/" + PAGE.theme + "/mail/email_routing.html";
                        }
                        return link;
                    };

                    manage.copyTextToClipboard = function() {
                        var textarea = document.createElement("textarea");
                        var copyText = document.getElementById("zoneFileText").textContent;
                        textarea.value = copyText;
                        document.body.appendChild(textarea);
                        textarea.select();
                        var copyResult = document.execCommand("copy");
                        if (copyResult) {
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("Successfully copied to the clipboard."),
                                closeable: true,
                                autoClose: 10000,
                                group: "zoneEditor",
                            });

                        } else {
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("Copy failed."),
                                closeable: true,
                                replace: false,
                                group: "zoneEditor",
                            });
                        }
                        document.body.removeChild(textarea);
                    };

                    manage.copy_zone_file = function() {
                        manage.copyMode = true;
                    };

                    manage.returnToEditor = function() {
                        manage.copyMode = false;
                    };


                    manage.createNewRecord = function(recordType) {
                        var type = recordType || "";
                        var record = {
                            record_type: recordType,
                            editing: true,
                            is_new: "1",
                        };

                        if (!type) {
                            if (Features.mx && !Features.simple && !Features.advanced) {
                                record.record_type = "MX";
                            } else {
                                record.record_type = "A";
                            }
                        }
                        var new_dmarc = new DMARCRecord();

                        var parsedRecord = new Record(record, new_dmarc);

                        manage.zone_records.push(parsedRecord);
                    };

                    manage.cancelRecordEdit = function(record, idx) {

                        // user cancels editing of existing record
                        if (record && record.is_new === "0") {
                            var cache = record.cache;
                            for (var key in cache) {
                                if (key) {
                                    record[key] = cache[key];
                                }
                            }
                            record.cache = cache;
                            record.editing = false;

                        // user cancels editing of new record
                        } else if (record && record.is_new === "1") {
                            manage.zone_records.splice(idx, 1);
                        } else {

                            // all records are cancelled
                            manage.zone_records.forEach(function(record) {
                                record.editing = false;
                            });
                        }
                    };

                    function formatSubmitObj(records) {
                        var submitObjs = records.map(function(record) {
                            var parsedRecord = {
                                dname: record.name,
                                ttl: record.ttl,
                                record_type: record.record_type,
                                line_index: record.line_index,
                                data: [],
                                is_new: record.is_new === "1",
                            };

                            // WARNING: THE ORDER OF EACH .push() IS SPECIFIC AND CAN NOT CHANGE
                            // It is the order of zone file data columns for the specific record type
                            switch (record.record_type) {
                                case "SOA":
                                    parsedRecord.data.push(record.mname);
                                    parsedRecord.data.push(record.rname);
                                    parsedRecord.data.push(parseInt(record.serial, 10));
                                    parsedRecord.data.push(parseInt(record.refresh));
                                    parsedRecord.data.push(parseInt(record.retry, 10));
                                    parsedRecord.data.push(parseInt(record.expire, 10));
                                    parsedRecord.data.push(parseInt(record.ttl, 10));
                                    break;
                                case "A":
                                    parsedRecord.data.push(record.a_address);
                                    break;
                                case "AAAA":
                                    parsedRecord.data.push(record.aaaa_address);
                                    break;
                                case "AFSDB":
                                    parsedRecord.data.push(record.subtype);
                                    parsedRecord.data.push(record.hostname);
                                    break;
                                case "CAA":
                                    parsedRecord.data.push(record.flag);
                                    parsedRecord.data.push(record.tag);
                                    parsedRecord.data.push(record.value);
                                    break;
                                case "CNAME":
                                    parsedRecord.data.push(record.cname);
                                    break;
                                case "DNAME":
                                    parsedRecord.data.push(record.dname);
                                    break;
                                case "DS":
                                    parsedRecord.data.push(parseInt(record.keytag, 10));
                                    parsedRecord.data.push(getDSAlgorithmByAlgo(record.algorithm));
                                    parsedRecord.data.push(getDSDigestTypeAlgo(record.digtype));
                                    parsedRecord.data.push(record.digest);
                                    break;
                                case "HINFO":
                                    parsedRecord.data.push(record.cpu);
                                    parsedRecord.data.push(record.os);
                                    break;
                                case "LOC":
                                    parsedRecord.data.push(record.latitude);
                                    parsedRecord.data.push(record.longitude);
                                    parsedRecord.data.push(record.altitude + "m");
                                    parsedRecord.data.push(record.size + "m");
                                    parsedRecord.data.push(record.horiz_pre + "m");
                                    parsedRecord.data.push(record.vert_pre + "m");
                                    break;
                                case "MX":
                                    parsedRecord.data.push(parseInt(record.priority, 10));
                                    parsedRecord.data.push(record.exchange);
                                    break;
                                case "NS":
                                    parsedRecord.data.push(record.nsdname);
                                    break;
                                case "NAPTR":
                                    parsedRecord.data.push(parseInt(record.order, 10));
                                    parsedRecord.data.push(parseInt(record.preference, 10));
                                    parsedRecord.data.push(record.flags);
                                    parsedRecord.data.push(record.service);
                                    parsedRecord.data.push(record.regexp);
                                    parsedRecord.data.push(record.replacement);
                                    break;
                                case "PTR":
                                    parsedRecord.data.push(record.ptrdname);
                                    break;
                                case "RP":
                                    parsedRecord.data.push(record.mbox || ".");
                                    parsedRecord.data.push(record.txtdname || ".");
                                    break;
                                case "SRV":
                                    parsedRecord.data.push(parseInt(record.priority, 10));
                                    parsedRecord.data.push(parseInt(record.weight, 10));
                                    parsedRecord.data.push(parseInt(record.port, 10));
                                    parsedRecord.data.push(record.target);
                                    break;
                                case "TXT":
                                    if (!record.is_dmarc) {
                                        parsedRecord.data = record.txtdata;
                                    } else {
                                        if (!record.rawTabSelected) {
                                            manage.updateTXTFromDMARCRecord(record);
                                        }
                                        parsedRecord.data.push(record.txtdata);
                                    }
                                    break;
                            }
                            return parsedRecord;
                        });
                        return submitObjs;
                    }

                    manage.getAddFormState = function() {
                        return manage.add_zr_form.$invalid ? "invalid" : "valid";
                    };

                    manage.isEditingRecords = function() {
                        var record;
                        for (var i = 0, len = manage.zone_records.length; i < len; i++) {
                            record = manage.zone_records[i];
                            if (record.editing) {
                                return true;
                            }
                        }
                        return false;
                    };

                    manage.handleRowKeypress = function handleRowKeypress(event, zone_rec) {

                        // cf. https://www.tjvantoll.com/2013/01/01/enter-should-submit-forms-stop-messing-with-that/
                        if (zone_rec.editing && (event.keyCode === 13)) {

                            // Don’t click() the form’s first submit button:
                            event.preventDefault();

                            // Don’t submit() the form:
                            event.stopPropagation();

                            var submitter = document.getElementById("inline_add_record_button_" + zone_rec._id);

                            // Defer the record-submitter’s click() button
                            $timeout(function() {
                                submitter.click();
                            }, 0);
                        }
                    };

                    manage.saveRecords = function(record) {
                        var saveArgs;

                        if (manage.add_zr_form.$invalid) {

                            // if the user click 'Save All' set all controls to dirty
                            if (!record) {
                                for (var key in manage.add_zr_form) {
                                    if (manage.add_zr_form[key] && manage.add_zr_form[key].$setDirty) {
                                        manage.add_zr_form[key].$setDirty();
                                    }
                                }

                            // if user clicks 'Save Record' from a specific row check if any of the specific controls are invalid
                            // save the records if they are valid
                            } else {
                                var ctrlRegex = new RegExp("_" + record._id + "$");
                                var ctrls = [];
                                for (var formKey in manage.add_zr_form) {
                                    if (formKey) {
                                        var isCtrl;
                                        isCtrl = ctrlRegex.test(formKey);
                                        if (isCtrl) {
                                            ctrls.push(manage.add_zr_form[formKey]);
                                        }
                                    }
                                }
                                var invalidCtrls = ctrls.filter(function(ctrl) {
                                    return ctrl.$invalid;
                                });
                                if (invalidCtrls.length) {
                                    invalidCtrls.forEach(function(ctrl) {
                                        ctrl.$setDirty();
                                    });
                                } else {
                                    saveArgs = [record];
                                }
                            }
                        } else {
                            saveArgs = record ? [record] : [];
                        }

                        if (saveArgs && this.checkRecordSets()) {
                            return manage._saveRecords.apply(manage, saveArgs);
                        }
                    };

                    manage._saveRecords = function(record) {
                        var recordsToSubmit = [];
                        manage.recordsInProgress = [];
                        var filteredRecords = _.filter(manage.zone_records, "editing");
                        if (record) {
                            var idx = filteredRecords.indexOf(record);
                            filteredRecords.splice(idx, 1);
                            manage.recordsInProgress = filteredRecords;
                            recordsToSubmit.push(record);
                        } else {
                            recordsToSubmit = filteredRecords;
                        }


                        recordsToSubmit.forEach(function(record) {
                            if (record.is_new) {
                                updateFilterListFilter(record, "add");
                            }
                        });

                        var submitObjs = formatSubmitObj(recordsToSubmit);

                        manage.save_in_progress = true;
                        return Zones.saveRecords(manage.domain, submitObjs, manage.serial)
                            .then(function() {
                                if (recordsToSubmit.length > 1) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully saved [quant,_1,record,records] for “[_2]”.", recordsToSubmit.length, _.escape(manage.domain)),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor",
                                    });
                                } else {
                                    var messageRecord = recordsToSubmit[0];
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully saved the following [_1] record for “[_2]”: “[_3]”.", messageRecord.record_type, _.escape(manage.domain), _.escape(Zones.trimTrailingDot(messageRecord.name))),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor",
                                    });
                                }

                                return load();
                            }).catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor",
                                });
                            }).finally(function() {
                                manage.save_in_progress = false;
                            });
                    };

                    manage.field_has_error = function(form, fieldName) {
                        return form && fieldName && form[fieldName] && form[ fieldName ].$invalid && form[ fieldName ].$dirty;
                    };

                    // sorts the list so that new record rows are added to the top
                    // can not add new record to beginning of the array because the DOM does not re-render. multiple form fields end up having the same index, which means there are not unique ids. new record must be added to end of array to guarantee unique ids for every field
                    // can not manipulate DOM directly after adding record to array, as the actual DOM has not re-rendered yet and element does not exist yet
                    $scope.$watchCollection("manage.zone_records", function(newValue) {
                        manage.zone_records = _.sortBy(newValue, [function(record) {
                            record.cache = angular.copy(record);
                            return record.is_new !== "1";
                        }]);
                        table.loadData(manage.zone_records);
                        manage.filteredList = table.populate();
                    });

                    manage.edit_record = function(zoneRecord) {
                        zoneRecord.editing = true;
                    };

                    manage.confirm_delete_record = function(record) {
                        manage.cancelRecordEdit();
                        $uibModal.open({
                            templateUrl: "confirm_delete.html",
                            controller: RemoveRecordModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                record: function() {
                                    return record;
                                },
                            },
                        });
                    };

                    manage.confirm_reset_zone = function() {

                        // we do not want the user to do a reset if they are editing/adding
                        if (manage.isFormEditing()) {
                            return;
                        }

                        $uibModal.open({
                            templateUrl: "confirm_reset_zone.html",
                            controller: ResetZoneModalController,
                            controllerAs: "ctrl",
                        });
                    };

                    manage.refresh = function() {

                        // we do not want the user to refresh if they are editing/adding
                        if (manage.isFormEditing()) {
                            return;
                        }

                        return load();
                    };

                    function load() {
                        manage.is_loading = true;
                        return Zones.fetch(manage.domain)
                            .then(function(data) {
                                var recordData = data.parsedZoneData;
                                manage.default_ttl = data.defaultTTL;

                                manage.zone_records = [];
                                var dmarc_record = new DMARCRecord();
                                for (var i = 0, len = recordData.length; i < len; i++) {
                                    var zoneRecord = recordData[i];

                                    // if the user does not have the advanced feature,
                                    // do not display records that are cpanel generated/controlled
                                    if (Features.simple &&
                                    !Features.advanced &&
                                    zoneRecord.record_type !== "MX" &&
                                    manage.generated_domains[ zoneRecord.name ]) {
                                        continue;
                                    }

                                    if (
                                        ((zoneRecord.record_type === "A" || zoneRecord.record_type === "CNAME") && manage.Features.simple) ||
                                        (zoneRecord.record_type === "MX" && manage.Features.mx) ||
                                        (zoneRecord.record_type !== "MX" && manage.Features.advanced)
                                    ) {
                                        zoneRecord.is_new = "0";
                                        zoneRecord = new Record(zoneRecord, dmarc_record);
                                        zoneRecord.editing = false;
                                        manage.zone_records.push(zoneRecord);
                                    }
                                }
                                filterListFilter();
                                manage.cancelRecordEdit();
                                manage.recordsInProgress.forEach(function(record) {
                                    if (record.is_new === "1") {
                                        manage.zone_records.push(record);
                                    } else {
                                        var removeRecord = manage.zone_records.filter(function(rRecord) {
                                            return rRecord.line_index === record.line_index;
                                        });
                                        removeRecord = removeRecord[0];
                                        var idx = manage.zone_records.indexOf(removeRecord);
                                        manage.zone_records.splice(idx, 1, record);
                                    }
                                });
                                var soa = manage.zone_records.find(function(record) {
                                    return record.record_type === "SOA";
                                });

                                manage.serial = soa ? soa.serial : null;
                            })
                            .catch(function(error) {

                                // If we get an error at this point, we assume that the user
                                // should not be able to do anything on the page.
                                manage.loading_error = true;
                                manage.loading_error_message = _.escape(error);
                            })
                            .finally(function() {
                                manage.is_loading = false;
                                manage.add_zr_form.$setPristine();
                            });
                    }

                    manage.updateRecordTemplate = function(record) {
                        record.editTemplate = manage.getRecordTemplate(record);
                    };

                    manage._findRecordTypeByType = function(type) {
                        for (var i = 0; i < manage.recordTypes.length; i++) {
                            if (manage.recordTypes[ i ].type === type) {
                                return manage.recordTypes[ i ];
                            }
                        }
                        return null;
                    };

                    manage.viewRecordTemplates = function(type) {
                        var view = "";

                        manage.recordTypes.forEach(function(record) {
                            if (record.type === type) {
                                view = record.viewTemplate;
                            }
                        });

                        return view;
                    };


                    manage._featureAllowed = function(type) {
                        var allowed = false;
                        switch (type) {
                            case "A":
                            case "CNAME":
                                allowed = (manage.Features.simple || manage.Features.advanced);
                                break;
                            case "MX":
                                allowed = manage.Features.mx;
                                break;
                            case "SRV":
                            case "AAAA":
                            case "CAA":
                            case "TXT":
                                allowed = manage.Features.advanced;
                                break;
                            case "DNAME":
                            case "HINFO":
                            case "NS":
                            case "RP":
                            case "PTR":
                            case "NAPTR":
                            case "DS":
                            case "AFSDB":
                            case "SOA":
                            case "LOC":
                                allowed = manage.Features.whmOnly;
                                break;
                        }
                        return allowed;
                    };

                    manage.filterRowRecordsDisplay = function(record) {
                        var disallowedTypes = ["SOA", "DMARC"];
                        return (disallowedTypes.indexOf(record.type) === -1);
                    };

                    manage.getRecordTemplate = function(record) {
                        var recordType = record.record_type;

                        if (record.is_dmarc) {
                            recordType = "DMARC";
                        }

                        var recordTypeObj = manage._findRecordTypeByType(recordType);
                        var template = recordTypeObj ? recordTypeObj.template : "";
                        return template;
                    };

                    manage.init = function() {
                        manage.is_loading = true;
                        if (!Features.whmOnly || (Features.whmOnly && $location.path() === "/manage/")) {
                            if (defaultInfo.otherRecordsInterface) {
                                manage.showOtherRecordTypeOption = true;
                                manage.otherRecordTypeHref = defaultInfo.otherRecordsInterface + "?domainselect=" + manage.domain;
                            }
                            $recordTypes.get().then(function _recordTypesReceived(recordTypes) {
                                manage.recordTypes = recordTypes;
                            });

                            return Zones.fetch_generated_domains(manage.domain, true)
                                .then(function(data) {
                                    manage.generated_domains = data;
                                    return load();
                                })
                                .catch(function(error) {
                                    manage.loading_error = true;
                                    manage.loading_error_message = _.escape(error);
                                });
                        } else {
                            if (Features.whmOnly) {
                                Zones.exportZoneFile(manage.domain).then(function(response) {
                                    manage.copyable_zone_file = response.trim();
                                    manage.is_loading = false;
                                });
                            }
                        }

                    };

                    manage.init();
                },
            ]);

        return {
            namespace: MODULE_NAMESPACE,
        };
    }

);

/*
# zone_editor/services/dnssec.js                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/dnssec',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/io/api",
        "cjt/io/whm-v1",
        "cjt/services/APIService",
        "cjt/services/viewNavigationApi"
    ],
    function(angular, _, LOCALE, APIREQUEST) {
        "use strict";

        var app = angular.module("whm.zoneEditor.services.dnssec", ["cjt2.services.api"]);

        var ONE_YEAR = 60 * 60 * 24 * 365;  // This is a suggested rotation time and does not need to be absolutely correct, hence no leap year check
        var HALF_YEAR = ONE_YEAR / 2;

        /**
         * Service wrapper for dnssec
         *
         * @module DnsSecService
         *
         * @param  {Object} $q angular $q object
         * @param  {Object} APIService cjt2 api service
         */
        var factory = app.factory("DnsSecService", ["$q", "APIService", "viewNavigationApi", function($q, APIService, viewNavigationApi) {
            var DnsSecApi = function() {};
            DnsSecApi.prototype = new APIService();

            angular.extend(DnsSecApi.prototype, {
                generate: generate,
                fetch: fetchDsRecords,
                activate: activate,
                deactivate: deactivate,
                remove: remove,
                importKey: importKey,
                exportKey: exportKey,
                exportPublicDnsKey: exportPublicDnsKey,
                copyTextToClipboard: copyTextToClipboard,
                goToInnerView: goToInnerView,
                getSuggestedKeyRotationDate: getSuggestedKeyRotationDate
            });


            return new DnsSecApi();

            /**
             * @typedef GenerateKeyDetails
             * @type Object
             * @property {EnabledDetails} enabled
             */

            /**
             * @typedef EnabledDetails
             * @type Object
             * @property {EnabledDomainDetails} your domain name
             */

            /**
             * @typedef EnabledDomainDetails
             * @type Object
             * @property {string} nsec_version - the nsec version for the key.
             * @property {Number} enabled - 1 if enabled, 0 if not.
             * @property {string} new_key_id - the id of the key.
             */

            /**
             * Generates DNSSEC keys according to a particular setup
             *
             * @method generate
             * @async
             * @param {string} domain - the domain
             * @param {string} [algoNum] - the algorithm number
             * @param {string} [setup] - how to setup the keys, "classic" or "simple"
             * @param {boolean} [active] - set the status of the key
             * @return {GenerateKeyDetails} Details about the key.
             * @throws When the back-end throws errors.
             */
            function generate(domain, algoNum, setup, active) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "enable_dnssec_for_domains");
                apiCall.addArgument("domain", domain);

                if (algoNum !== void 0) {
                    apiCall.addArgument("algo_num", algoNum);
                }

                if (setup !== void 0) {
                    apiCall.addArgument("key_setup", setup);
                }

                if (active !== void 0) {
                    apiCall.addArgument("active", (active) ? 1 : 0);
                }

                return this.deferred(apiCall).promise
                    .then(function(response) {
                        var domainObj = response.data.pop();
                        var returnObj = { enabled: {} };
                        returnObj.enabled[domainObj.domain] = domainObj;
                        return returnObj;
                    });
            }

            /**
             * @typedef FetchDSRecordsReturn
             * @type Object
             * @property {FetchDSRecordsKeyDetails} keys
             */

            /**
             * @typedef FetchDSRecordsKeyDetails
             * @type Object
             * @property {Number} active - 1 if active, 0 if not.
             * @property {string} algo_desc - the key algorithm.
             * @property {string} algo_num - the number for the key algorithm.
             * @property {string} algo_tag - the tag for the key algorithm.
             * @property {string} bits - the number of bits for the key algorithm.
             * @property {string} created - the unix epoch when the key was created.
             * @property {Digests[]} digests - the digests for the key; only a KSK or CSK will have this.
             * @property {string} flags - the flags of the key.
             * @property {string} key_id - the id of the key.
             * @property {string} key_tag - the tag of the key.
             * @property {string} key_type - the type of the key (either ZSK, KSK, CSK).
             */

            /**
             * @typedef Digests
             * @type Object
             * @property {string} algo_desc - The algorithm for the digest.
             * @property {string} algo_num - The number for the digest algorithm.
             * @property {string} digest - The digest hash.
             */

            /**
             * Retrieve the DS records for a domain
             *
             * @method fetchDsRecords
             * @async
             * @param {string} domain - the domain
             * @return {FetchDSRecordsReturn} - An object of all keys for this domain.
             * @throws When the back-end throws errors.
             */
            function fetchDsRecords(domain) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "fetch_ds_records_for_domains");
                apiCall.addArgument("domain", domain);

                return this.deferred(apiCall).promise
                    .then(function(response) {
                        var keys = [];

                        if (response.data && response.data.length) {
                            var domainObj = response.data.pop();
                            if (domainObj.ds_records.keys) {
                                keys = Object.keys(domainObj.ds_records.keys).map(function(key) {
                                    return domainObj.ds_records.keys[key];
                                });
                            }
                        }

                        return _.chain(keys)
                            .orderBy(["key_type", "active", function(i) {
                                return Number(i.key_tag); // convert to number so it sorts numerically rather than lexically
                            }], ["asc", "desc", "asc"])
                            .value();

                    });
            }

            /**
             * @typedef ActivateKeyReturn
             * @type Object
             * @property {string} domain - The domain for the key.
             * @property {string} key_id - The id of the key.
             * @property {Number} success - 1 for success, 0 for failure.
             */

            /**
             * Activate a DNSSEC key
             *
             * @method activate
             * @async
             * @param {string} domain - the domain
             * @param {string|number} keyId - the id of the key
             * @return {ActivateKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function activate(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "activate_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // The API call can succeed but you can still get an error message
                        // so check for that message and return it
                        if (!response.status) {
                            return $q.reject(response.error);
                        }

                        return response.data;
                    });
            }

            /**
             * Deactivate a DNSSEC zone key
             *
             * @method deactivate
             * @async
             * @param {string} domain - the domain
             * @param {string|number} keyId - the id of the key
             * @return {ActivateKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function deactivate(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "deactivate_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return response.data;
                    });
            }

            /**
             * Remove a DNSSEC zone key
             *
             * @method remove
             * @async
             * @param {string} domain - the domain
             * @param {string|number} keyId - the id of the key
             * @return {ActivateKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function remove(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remove_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return response.data;
                    });
            }

            /**
             * @typedef ImportKeyReturn
             * @type Object
             * @property {string} domain - The domain for the key.
             * @property {string} new_key_id - The id of the new key.
             * @property {Number} success - 1 for success, 0 for failure.
             */

            /**
             * Imports a DNSSEC zone key
             *
             * @method importKey
             * @async
             * @param {string} domain - the domain
             * @param {string} keyType - type of key, KSK or ZSK
             * @param {string} key - the key data in a text format
             * @return {ImportKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function importKey(domain, keyType, key) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "import_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_data", key);
                apiCall.addArgument("key_type", keyType.toLocaleLowerCase("en-US"));

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return response.data;
                    });
            }

            /**
             * @typedef ExportKeyReturn
             * @type Object
             * @property {string} domain - The domain for the key.
             * @property {string} key_content - The key data in a text format.
             * @property {string} key_id - The id of the key.
             * @property {string} key_tag - The tag for the key.
             * @property {string} key_type - The type of the key.
             * @property {Number} success - 1 for success, 0 for failure.
             */


            /**
             * Exports a DNSSEC zone key
             *
             * @method exportKey
             * @async
             * @param {string} domain - the domain
             * @param {string} keyId - the id of the key
             * @return {ExportKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function exportKey(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "export_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        return response.data;
                    });
            }

            /**
             * @typedef ExportPublicDnsKeyReturn
             * @type Object
             * @property {string} key_id - The id of the key.
             * @property {string} dnskey - The public dns key for the specified dnssec key.
             */

            /**
             * Exports the public DNSKEY
             *
             * @method exportPublicDnsKey
             * @async
             * @param {string} domain - the domain
             * @param {string} keyId - the id of the key
             * @return {ExportPublicDnsKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function exportPublicDnsKey(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "export_zone_dnskey");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        return response.data;
                    });
            }

            /**
             * Puts some text on the clipboard
             *
             * @method copyTextToClipboard
             * @param {string} text - the text you want to put on the clipboard
             * @return Nothing
             * @throws When the copy command does not succeed
             */
            function copyTextToClipboard(text) {
                var textArea = document.createElement("textarea");
                textArea.value = text;
                document.body.appendChild(textArea);
                textArea.select();
                var success = document.execCommand("copy");
                if (!success) {
                    throw LOCALE.maketext("Copy failed.");
                }
                document.body.removeChild(textArea);
            }

            /**
             * Helper function to navigate to "sub-views" within dnssec
             *
             * @method goToInnerView
             * @param {string} view - the view you want to go to.
             * @param {string} domain - the domain associated with the key.
             * @param {string} keyId - the key id; used to load information about the key on that view.
             * @return {$location} The Angular $location service used to perform the view changes.
             */
            function goToInnerView(view, domain, keyId) {
                var path = "/dnssec/" + view;
                var query = { domain: domain };
                if (keyId) {
                    query.keyid = keyId;
                }
                return viewNavigationApi.loadView(path, query);
            }

            /**
             * Calculates the suggested rotation date for a key
             *
             * @method getSuggestedKeyRotationDate
             * @param {number|string} date - an epoch date
             * @param {string} keyType - key type, either ksk, zsk, or csk
             * @return {number} The suggested rotation date
             */
            function getSuggestedKeyRotationDate(date, keyType) {
                if (typeof date === "string") {
                    date = Number(date);
                }

                var suggestedDate = date;
                if (keyType.toLowerCase() === "zsk") {
                    suggestedDate += HALF_YEAR;
                } else {
                    suggestedDate += ONE_YEAR;
                }
                return suggestedDate;
            }

        }]);

        return factory;
    }
);

/*
# zone_editor/views/dnssec.js                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'shared/js/zone_editor/views/dnssec',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/directives/alert",
        "cjt/services/alertService",
        "app/services/dnssec",
        "uiBootstrap"
    ],
    function(angular, _, LOCALE, PARSE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssec";
        var app = angular.module(MODULE_NAMESPACE, []);

        /**
         * Create Controller for DNSSEC view
         *
         * @module DnsSecController
         */
        app.controller(
            "DnsSecController", [
                "$scope",
                "$q",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "$uibModal",
                function(
                    $scope,
                    $q,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    $uibModal) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";
                    dnssec.is_generating = false;
                    dnssec.keys = [];
                    dnssec.isRTL = PAGE.isRTL;

                    var EPOCH_FOR_TODAY = Date.now() / 1000;

                    /**
                     * Creates a controller for the Deactivate Key modal
                     *
                     * @method DeactivateKeyModalController
                     * @param {object} $uibModalInstance - the modal object
                     * @param {object} key - a key object
                     */
                    function DeactivateKeyModalController($uibModalInstance, key) {
                        var ctrl = this;
                        ctrl.key = key;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return DnsSecService.deactivate(dnssec.domain, key.key_id)
                                .then(function(result) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("Key “[_1]” successfully deactivated.", key.key_tag),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor"
                                    });
                                    key.active = false;
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor"
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }
                    DeactivateKeyModalController.$inject = ["$uibModalInstance", "key"];

                    /**
                     * Creates a controller for the Delete Key modal
                     *
                     * @method DeleteKeyModalController
                     * @param {object} $uibModalInstance - the modal object
                     * @param {object} key - a key object
                     */
                    function DeleteKeyModalController($uibModalInstance, key) {
                        var ctrl = this;
                        ctrl.key = key;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return DnsSecService.remove(dnssec.domain, key.key_id)
                                .then(function(result) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("Key “[_1]” successfully deleted.", key.key_tag),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor"
                                    });
                                    return dnssec.load();
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        closeable: true,
                                        replace: false,
                                        group: "zoneEditor"
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }
                    DeleteKeyModalController.$inject = ["$uibModalInstance", "key"];

                    /**
                     * Creates a controller for the Generate Keys modal
                     *
                     * @method GenerateModalController
                     * @param {object} $uibModalInstance - the modal object
                     */
                    function GenerateModalController($uibModalInstance) {
                        var ctrl = this;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return dnssec.generate()
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                        ctrl.goToGenerate = function() {
                            $uibModalInstance.dismiss("cancel");
                            return dnssec.goToInnerView("generate");
                        };
                    }
                    GenerateModalController.$inject = ["$uibModalInstance"];

                    dnssec.goToInnerView = function(view, keyId) {
                        return DnsSecService.goToInnerView(view, dnssec.domain, keyId);
                    };

                    function parseDnssecKeys(dnssecKeys) {
                        for (var i = 0, len = dnssecKeys.length; i < len; i++) {
                            var key = dnssecKeys[i];
                            key.active = PARSE.parsePerlBoolean(key.active);
                            key.bits_msg = LOCALE.maketext("[quant,_1,bit,bits]", key.bits);
                            key.isExpanded = false;
                            if (key.created !== void 0 && key.created !== "0") {
                                var suggestedRotationDate = DnsSecService.getSuggestedKeyRotationDate(key.created, key.key_type);
                                key.should_rotate = suggestedRotationDate < EPOCH_FOR_TODAY;
                                key.created = LOCALE.local_datetime(key.created, "datetime_format_medium");
                            } else {
                                key.created = LOCALE.maketext("Unknown");
                            }
                        }
                    }

                    dnssec.expandKey = function(key, isExpanded) {
                        key.isExpanded = isExpanded;
                    };

                    dnssec.activate = function(key) {
                        return DnsSecService.activate(dnssec.domain, key.key_id)
                            .then(function(result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key “[_1]” successfully activated.", key.key_tag),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });
                                key.active = true;
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            });
                    };

                    dnssec.confirmDeactivateKey = function(key) {
                        $uibModal.open({
                            templateUrl: "dnssec_confirm_deactivate.html",
                            controller: DeactivateKeyModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                key: function() {
                                    return key;
                                },
                            }
                        });
                    };

                    dnssec.confirmDeleteKey = function(key) {
                        $uibModal.open({
                            templateUrl: "dnssec_confirm_delete.html",
                            controller: DeleteKeyModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                key: function() {
                                    return key;
                                },
                            }
                        });
                    };

                    dnssec.launchGenerateModal = function(key) {
                        $uibModal.open({
                            templateUrl: "quick_generate.html",
                            controller: GenerateModalController,
                            controllerAs: "ctrl",
                        });
                    };

                    dnssec.generate = function() {
                        dnssec.is_generating = true;
                        return DnsSecService.generate(dnssec.domain)
                            .then(function(result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key generated successfully."),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });

                                return dnssec.goToInnerView("dsrecords", result.enabled[dnssec.domain].new_key_id);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            })
                            .finally(function() {
                                dnssec.is_generating = false;
                            });
                    };

                    dnssec.load = function() {
                        dnssec.keys = [];
                        dnssec.is_loading = true;
                        return DnsSecService.fetch(dnssec.domain)
                            .then(function(result) {
                                dnssec.keys = result;
                                parseDnssecKeys(dnssec.keys);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            })
                            .finally(function() {
                                dnssec.is_loading = false;
                            });
                    };

                    dnssec.init = function() {
                        if (Features.dnssec) {
                            dnssec.load();
                        } else {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);

/*
# zone_editor/views/dnssec_generate.js             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'shared/js/zone_editor/views/dnssec_generate',[
        "angular",
        "cjt/util/locale",
        "lodash",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/dnssec",
        "uiBootstrap",
        "cjt/services/cpanel/componentSettingSaverService"
    ],
    function(angular, LOCALE, _, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecGenerate";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecGenerateController",
            [
                "$scope",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "defaultInfo",
                "$document",
                "componentSettingSaverService",
                function(
                    $scope,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    defaultInfo,
                    $document,
                    componentSettingSaverService
                ) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.settings = {};
                    var SAVED_SETTINGS_DEFAULTS = {
                        showAllHelp: true,
                    };

                    dnssec.isRTL = defaultInfo.isRTL;

                    // setup defaults
                    dnssec.details = {
                        setup: "classic",
                        algorithm: 8,
                        active: true
                    };

                    dnssec.backToListView = function() {
                        return DnsSecService.goToInnerView("", dnssec.domain);
                    };

                    dnssec.goToDSRecords = function(keyId) {
                        return DnsSecService.goToInnerView("dsrecords", dnssec.domain, keyId);
                    };

                    dnssec.toggleHelp = function() {
                        dnssec.settings.showAllHelp = !dnssec.settings.showAllHelp;
                        componentSettingSaverService.set("zone_editor_dnssec", dnssec.settings);
                    };

                    dnssec.isClassicSetup = function() {
                        return dnssec.details.setup === "classic";
                    };

                    /**
                     * Ensure we select ECDSA when 'simple' is selected
                     */
                    dnssec.onSetupSelect = function($event) {
                        var value = $event.target.value;
                        if (value === "simple") {
                            dnssec.details.algorithm = 13;
                        }
                    };

                    dnssec.generate = function(details) {
                        return DnsSecService.generate(dnssec.domain, details.algorithm, details.setup, details.active)
                            .then(function(result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key generated successfully"),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });

                                dnssec.goToDSRecords(result.enabled[dnssec.domain].new_key_id);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            });
                    };

                    dnssec.init = function() {
                        $document[0].body.scrollIntoView();  // scroll to top of window

                        // get the settings for the app
                        var settings = componentSettingSaverService.getCached("zone_editor_dnssec").cachedValue;
                        _.merge(dnssec.settings, SAVED_SETTINGS_DEFAULTS, settings || {});

                        if (!Features.dnssec) {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);

/*
# zone_editor/views/dnssec_ds_records.js           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'shared/js/zone_editor/views/dnssec_ds_records',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/dnssec",
        "uiBootstrap"
    ],
    function(angular, _,  LOCALE, PARSE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecDSRecords";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecDSRecordsController",
            ["$scope", "$q", "$routeParams", "DnsSecService", FeaturesService.serviceName, "alertService", "defaultInfo",
                function($scope, $q, $routeParams, DnsSecService, Features, alertService, defaultInfo) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;
                    dnssec.keyId = $routeParams.keyid;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.keyContent = {};

                    dnssec.isRTL = defaultInfo.isRTL;

                    dnssec.goToInnerView = function(view, keyId) {
                        return DnsSecService.goToInnerView(view, dnssec.domain, keyId);
                    };

                    dnssec.backToListView = function() {
                        return dnssec.goToInnerView("");
                    };

                    dnssec.putOnClipboard = function(text) {
                        try {
                            DnsSecService.copyTextToClipboard(text);
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("Successfully copied to the clipboard."),
                                closeable: true,
                                replace: false,
                                autoClose: 10000,
                                group: "zoneEditor"
                            });
                        } catch (error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "zoneEditor"
                            });
                        }
                    };

                    function getKeyDetails(keys, keyId) {
                        var key = {};
                        keyId = parseInt(keyId);
                        for (var i = 0, len = keys.length; i < len; i++) {
                            var tempkey = keys[i];
                            if (tempkey.key_id === keyId) {
                                key = {
                                    active: PARSE.parsePerlBoolean(tempkey.active),
                                    algoDesc: tempkey.algo_desc,
                                    algoNum: tempkey.algo_num,
                                    algoTag: tempkey.algo_tag,
                                    flags: tempkey.flags,
                                    keyTag: tempkey.key_tag,
                                    keyId: tempkey.key_id,
                                    bits: tempkey.bits,
                                    bitsMsg: LOCALE.maketext("[quant,_1,bit,bits]", tempkey.bits),
                                    created: (tempkey.created !== void 0 && tempkey.created !== "0") ? LOCALE.local_datetime(tempkey.created, "datetime_format_medium") : LOCALE.maketext("Unknown"),
                                    digests: tempkey.digests.map(function(key) {
                                        return {
                                            algoDesc: key.algo_desc,
                                            algoNum: key.algo_num,
                                            digest: key.digest,
                                        };
                                    })
                                };
                                return key;
                            }
                        }
                        return;
                    }

                    dnssec.load = function() {
                        dnssec.is_loading = true;
                        return DnsSecService.fetch(dnssec.domain)
                            .then(function(result) {
                                var content;
                                if (result.length) {
                                    content = getKeyDetails(result, dnssec.keyId);
                                }

                                if (!content) {
                                    dnssec.loading_error = true;
                                    dnssec.loading_error_message = LOCALE.maketext("The [asis,DNSSEC] key you were trying to view does not exist.");
                                }
                                dnssec.keyContent = content;
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            })
                            .finally(function() {
                                dnssec.is_loading = false;
                            });
                    };

                    dnssec.init = function() {
                        if (Features.dnssec) {
                            return dnssec.load();
                        } else {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);

/*
# zone_editor/views/dnssec_import.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'shared/js/zone_editor/views/dnssec_import',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "app/services/dnssec",
        "uiBootstrap",
        "cjt/services/cpanel/componentSettingSaverService"
    ],
    function(angular, _, LOCALE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecImport";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecImportController",
            [
                "$scope",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "defaultInfo",
                "componentSettingSaverService",
                function(
                    $scope,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    defaultInfo,
                    componentSettingSaverService) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;
                    dnssec.keyId = $routeParams.keyid;

                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.settings = {};
                    var SAVED_SETTINGS_DEFAULTS = {
                        showAllHelp: true,
                    };

                    dnssec.isRTL = defaultInfo.isRTL;

                    // setup defaults
                    dnssec.details = {
                        keyToImport: "",
                        keyType: "KSK"
                    };

                    dnssec.goToInnerView = function(view, keyId) {
                        return DnsSecService.goToInnerView(view, dnssec.domain, keyId);
                    };

                    dnssec.backToListView = function() {
                        alertService.clear(void 0, "zoneEditor");
                        return dnssec.goToInnerView("");
                    };

                    dnssec.goToDSRecords = function(keyId) {
                        return dnssec.goToInnerView("dsrecords", keyId);
                    };

                    dnssec.toggleHelp = function() {
                        dnssec.settings.showAllHelp = !dnssec.settings.showAllHelp;
                        componentSettingSaverService.set("zone_editor_dnssec", dnssec.settings);
                    };

                    dnssec.importKey = function(details) {
                        dnssec.importForm.$submitted = true;

                        if (!dnssec.importForm.$valid || dnssec.importForm.$pending) {
                            return;
                        }

                        return DnsSecService.importKey(dnssec.domain, details.keyType, details.keyToImport)
                            .then(function(result) {
                                alertService.clear(void 0, "zoneEditor");
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key imported successfully"),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });

                                dnssec.goToDSRecords(result.new_key_id);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            });
                    };


                    dnssec.init = function() {

                        // get the settings for the app
                        var settings = componentSettingSaverService.getCached("zone_editor_dnssec").cachedValue;
                        _.merge(dnssec.settings, SAVED_SETTINGS_DEFAULTS, settings || {});

                        if (!Features.dnssec) {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);

/*
# zone_editor/views/dnssec_export.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'shared/js/zone_editor/views/dnssec_export',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "app/services/dnssec",
        "uiBootstrap",
        "cjt/services/cpanel/componentSettingSaverService"
    ],
    function(angular, _, LOCALE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecExport";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecExportController",
            [
                "$scope",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "defaultInfo",
                "componentSettingSaverService",
                function(
                    $scope,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    defaultInfo,
                    componentSettingSaverService) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;
                    dnssec.keyId = $routeParams.keyid;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.isRTL = defaultInfo.isRTL;

                    dnssec.backToListView = function() {
                        return DnsSecService.goToInnerView("", dnssec.domain);
                    };

                    dnssec.putOnClipboard = function(text) {
                        try {
                            DnsSecService.copyTextToClipboard(text);
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("Successfully copied to the clipboard."),
                                closeable: true,
                                replace: false,
                                autoClose: 10000,
                                group: "zoneEditor"
                            });
                        } catch (error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "zoneEditor"
                            });
                        }
                    };

                    dnssec.load = function() {
                        dnssec.is_loading = true;
                        return DnsSecService.exportKey(dnssec.domain, dnssec.keyId)
                            .then(function(result) {
                                dnssec.keyContent = result.key_content;
                                dnssec.keyTag = result.key_tag;
                                dnssec.keyType = result.key_type;
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            })
                            .finally(function() {
                                dnssec.is_loading = false;
                            });
                    };

                    dnssec.init = function() {
                        if (!Features.dnssec) {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        } else {
                            dnssec.load();
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);

/*
# cpanel - base/sharedjs/zone_editor/views/dnssec_dnskey.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'shared/js/zone_editor/views/dnssec_dnskey',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "app/services/dnssec",
        "uiBootstrap",
        "cjt/services/cpanel/componentSettingSaverService"
    ],
    function(angular, _, LOCALE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecDnskey";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecDnskeyController",
            [
                "$scope",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "defaultInfo",
                "componentSettingSaverService",
                function(
                    $scope,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    defaultInfo,
                    componentSettingSaverService) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;
                    dnssec.keyId = $routeParams.keyid;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.isRTL = defaultInfo.isRTL;

                    dnssec.backToListView = function() {
                        return DnsSecService.goToInnerView("", dnssec.domain);
                    };

                    dnssec.putOnClipboard = function(text) {
                        try {
                            DnsSecService.copyTextToClipboard(text);
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("Successfully copied to the clipboard."),
                                closeable: true,
                                replace: false,
                                autoClose: 10000,
                                group: "zoneEditor"
                            });
                        } catch (error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "zoneEditor"
                            });
                        }
                    };

                    dnssec.load = function() {
                        dnssec.is_loading = true;
                        return DnsSecService.exportPublicDnsKey(dnssec.domain, dnssec.keyId)
                            .then(function(result) {
                                dnssec.publicDNSKEY = result.dnskey;
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            })
                            .finally(function() {
                                dnssec.is_loading = false;
                            });
                    };

                    dnssec.init = function() {
                        if (!Features.dnssec) {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        } else {
                            dnssec.load();
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);

/*
# directives/loc_validators.js                             Copyright 2022 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('shared/js/zone_editor/directives/loc_validators',[
    "angular",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, LOCALE, validationUtils) {

    "use strict";

    var latitudeLongitudeRegex = /^(\d+)\s(\d+)\s(\d+(?:\.\d+)?)\s([A-Z]+)$/;

    var latitudeDegreeRegex = /^[0-9]{1,2}$/;
    var latitudeHemisphereRegex = /^[NS]$/;

    var longitudeDegreeRegex = /^[0-9]{1,3}$/;
    var longitudeHemisphereRegex = /^[EW]$/;

    var minuteRegex = /^[0-9]{1,2}$/;
    var secondsRegex = /^[0-9]{1,2}(?:\.[0-9]{1,3})?$/;

    var validators = {

        /**
         * Validates that Latitude is in the correct format - DMS
         *
         * @method validateLatitude
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        validateLatitude: function(val) {
            var result = validationUtils.initializeValidationResult();

            var matches = val.match(latitudeLongitudeRegex);

            if (matches === null) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("Latitude must be entered in “Degree Minute Seconds Hemisphere” format. Example: “12 45 52.233 N”."));
                return result;
            }

            if (!latitudeDegreeRegex.test(matches[1]) || parseInt(matches[1]) > 90) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The first set of digits of Latitude are for Degrees. Degrees must be a 1 or 2 digit number between 0 and 90."));
            } else if (!minuteRegex.test(matches[2]) || parseInt(matches[2]) > 59) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The second set of digits of Latitude are for Minutes. Minutes must be a 1 or 2 digit number between 0 and 59."));
            } else if (!secondsRegex.test(matches[3]) || parseFloat(matches[3]) > 59.999) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The third set of digits of Latitude are for Seconds. Seconds can only have up to 3 decimal places, and must be between 0 and 59.999."));
            } else if (!latitudeHemisphereRegex.test(matches[4])) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The last character of Latitude is the hemisphere, which can only be N or S."));
            }

            return result;
        },

        /**
         * Validates that Longitude is in the correct format - DMS
         *
         * @method validateLongitude
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        validateLongitude: function(val) {
            var result = validationUtils.initializeValidationResult();

            var matches = val.match(latitudeLongitudeRegex);

            if (matches === null) {
                result.isValid = false;
                result.add("locLon", LOCALE.maketext("Longitude must be entered in “Degree Minute Seconds Hemisphere” format. Example: “105 40 33.452 W”."));
                return result;
            }

            if (!longitudeDegreeRegex.test(matches[1]) || parseInt(matches[1]) > 180) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The first set of digits of Longitude are for Degrees. Degrees must be a 1 to 2 digit number between 0 and 180."));
            } else if (!minuteRegex.test(matches[2]) || parseInt(matches[2]) > 59) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The second set of digits of Longitude are for Minutes. Minutes must be a 1 or 2 digit number between 0 and 59."));
            } else if (!secondsRegex.test(matches[3]) || parseFloat(matches[3]) > 59.999) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The third set of digits of Longitude are for Seconds. Seconds can only have up to 3 decimal places, and must be between 0 and 59.999."));
            } else if (!longitudeHemisphereRegex.test(matches[4])) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The last character of Longitude is the hemisphere, which can only be E or W."));
            }

            return result;
        }

    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "locValidators",
        description: "Validation library for LOC records.",
        version: 2.0,
    };
});

/*
# zone_editor/index.js                             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* require: false, define: false, PAGE: false */

define(
    'app/index',[
        "angular",
        "app/services/features",
        "app/services/recordTypes",
        "app/services/domains",
        "app/services/zones",
        "app/services/page_data_service",

        // Shared Zone Files
        "shared/js/zone_editor/views/domain_selection",
        "shared/js/zone_editor/views/manage",
        "shared/js/zone_editor/views/dnssec",
        "shared/js/zone_editor/views/dnssec_generate",
        "shared/js/zone_editor/views/dnssec_ds_records",
        "shared/js/zone_editor/views/dnssec_import",
        "shared/js/zone_editor/views/dnssec_export",
        "shared/js/zone_editor/views/dnssec_dnskey",
        "shared/js/zone_editor/directives/convert_to_full_record_name",
        "cjt/core",
        "shared/js/zone_editor/directives/base_validators",
        "shared/js/zone_editor/directives/dmarc_validators",
        "shared/js/zone_editor/directives/caa_validators",
        "shared/js/zone_editor/directives/ds_validators",
        "shared/js/zone_editor/directives/loc_validators",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "app/services/dnssec",
    ],
    function(angular,
        FeaturesService,
        RecordTypesService,
        DomainsService,
        ZonesService,
        PageDataService,
        DomainSelectionView,
        ManageView,
        DNSSECView,
        DNSSECGenerateView,
        DNSSECDSRecordsView,
        DNSSECImportView,
        DNSSECExportView,
        DNSSECDnsKeyView,
        ConvertToFullRecordName,
        CJT
    ) {

        "use strict";

        return function() {

            // First create the application
            angular.module("whm.zoneEditor", [
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "whm.zoneEditor.services.dnssec",
                DomainsService.namespace,
                ZonesService.namespace,
                PageDataService.namespace,
                RecordTypesService.namespace,
                FeaturesService.namespace,
                DomainSelectionView.namespace,
                ManageView.namespace,
                DNSSECView.namespace,
                DNSSECGenerateView.namespace,
                DNSSECDSRecordsView.namespace,
                DNSSECImportView.namespace,
                DNSSECExportView.namespace,
                DNSSECDnsKeyView.namespace,
                ConvertToFullRecordName.namespace,
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",
                    "cjt/directives/breadcrumbs",
                    "cjt/services/alertService",
                    "cjt/directives/alert",
                    "cjt/directives/alertList",
                    "cjt/services/cpanel/componentSettingSaverService",
                    "app/services/page_data_service",
                    "app/services/domains",
                    "app/services/zones",
                    "app/services/dnssec",
                    "app/services/features",
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("whm.zoneEditor");

                    app.value("RECORD_TYPES", PAGE.RECORD_TYPES);

                    // setup the defaults for the various services.
                    app.factory("defaultInfo", [
                        PageDataService.serviceName,
                        function(pageDataService) {
                            return pageDataService.prepareDefaultInfo(PAGE);
                        },
                    ]);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/", {
                                controller: "ListDomainsController",
                                controllerAs: "list",
                                templateUrl: "views/domain_selection.ptt",
                            });

                            $routeProvider.when("/manage/", {
                                controller: "ManageZoneRecordsController",
                                controllerAs: "manage",
                                templateUrl: "views/manage.ptt",
                            });

                            $routeProvider.when("/manage/copyzone", {
                                controller: "ManageZoneRecordsController",
                                controllerAs: "manage",
                                templateUrl: "views/copy_zone_file.ptt",
                            });

                            $routeProvider.when("/dnssec/", {
                                controller: "DnsSecController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec.ptt",
                            });

                            $routeProvider.when("/dnssec/generate", {
                                controller: "DnsSecGenerateController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_generate.ptt",
                            });

                            $routeProvider.when("/dnssec/dsrecords", {
                                controller: "DnsSecDSRecordsController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_ds_records.ptt",
                            });

                            $routeProvider.when("/dnssec/import", {
                                controller: "DnsSecImportController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_import.ptt",
                            });

                            $routeProvider.when("/dnssec/export", {
                                controller: "DnsSecExportController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_export.ptt",
                            });

                            $routeProvider.when("/dnssec/dnskey", {
                                controller: "DnsSecDnskeyController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_dnskey.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/",
                            });
                        },
                    ]);

                    app.run([
                        "componentSettingSaverService",
                        function(
                            componentSettingSaverService
                        ) {
                            componentSettingSaverService.register("zone_editor_dnssec");
                        },
                    ]);

                    BOOTSTRAP("#contentContainer", "whm.zoneEditor");

                });

            return app;
        };
    }
);

