/*
# zone_editor/services/zones.js                                   Copyright 2022 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* define: false */

define(
    [
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
