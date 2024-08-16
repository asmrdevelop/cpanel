/* eslint-disable camelcase */
/*
# zone_editor/services/zones.js                                   Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/io/api2-request",
        "cjt/io/uapi-request",
        "cjt/util/httpStatus",
        "cjt/core",
        "cjt/util/base64",
        "cjt/io/api2",
        "cjt/io/uapi",
    ],
    function(angular, _, LOCALE, API, API2REQUEST, UAPIREQUEST, HTTP_STATUS, CJT, BASE64) {

        "use strict";

        var app = angular.module("cpanel.zoneEditor.services.zones", []);
        var factory = app.factory("Zones", ["$q", function($q) {

            var store = {};

            store.zones = [];
            store.zone_serial_number = "";
            store.zoneDefaultTTL = null;
            store.generated_domains = [];

            function _saveRecords(zone, records) {
                var apiCall = new UAPIREQUEST.Class();
                apiCall.initialize("DNS", "mass_edit_zone");
                apiCall.addArgument("zone", zone);
                apiCall.addArgument("serial", store.zone_serial_number);

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

                store.zoneDefaultTTL = null;
                return store._promise(apiCall)
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            return response.status;
                        } else {
                            return $q.reject(response);
                        }
                    })
                    .catch(function(response) {
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return $q.reject(store.request_failure_message(response.status));
                    });
            }

            store._promise = function(apiCall) {
                return $q.when(API.promise(apiCall.getRunArguments()));
            };

            /**
             * Save new or modified zone records
             * @param zone - name of zone
             * @param records - records to update or create
             * @returns - a promise resolving to true if successful, or an error
             */
            store.saveRecords = function(zone, records) {

                // if the request comes from the 'quick add' buttons in the domain list there will only be one record in the array and it will have a property called 'from_domain_list' set to true
                if (records[0].from_domain_list) {

                    // store.fetch() sets store.zone_serial_number and store.zoneDefaultTTL
                    return store.fetch(zone)
                        .then(function() {
                            records.forEach(function(record) {
                                record["ttl"] = parseInt(store.zoneDefaultTTL, 10);
                            });
                            return _saveRecords(zone, records);
                        });
                } else {
                    return _saveRecords(zone, records);
                }
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
                var apiCall = new UAPIREQUEST.Class();
                apiCall.initialize("DNS", "parse_zone");
                apiCall.addArgument("zone", zone);

                return store._promise(apiCall)
                    .then(function(response) {
                        var parsedResponse = response.parsedResponse;

                        if (parsedResponse.status) {
                            var defaultTTL;
                            var record;
                            var parsedData = [];
                            for (var i = 0, len = parsedResponse.data.length; i < len; i++) {
                                record = parsedResponse.data[i];
                                if (record.type === "record") {
                                    if (record.record_type === "A" ||
                                        record.record_type === "AAAA" ||
                                        record.record_type === "CAA" ||
                                        record.record_type === "CNAME" ||
                                        record.record_type === "MX" ||
                                        record.record_type === "SRV" ||
                                        record.record_type === "TXT") {
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
                                            case "MX":
                                                record["priority"] = record.txtdata[0];
                                                record["exchange"] = store.trimTrailingDot(record.txtdata[1]);
                                                break;
                                            case "SRV":
                                                record["priority"] = record.txtdata[0];
                                                record["weight"] = record.txtdata[1];
                                                record["port"] = record.txtdata[2];
                                                record["target"] = store.trimTrailingDot(record.txtdata[3]);
                                                break;
                                            case "CAA":
                                                record["flag"] = record.txtdata[0];
                                                record["tag"] = record.txtdata[1];
                                                record["value"] = record.txtdata[2];
                                                break;
                                            case "CNAME":
                                                record["record"] = store.trimTrailingDot(record.txtdata[0]);
                                                break;
                                            default:
                                                record["record"] = record.txtdata[0];
                                                break;
                                        }
                                        parsedData.push(record);
                                    } else if (record.record_type === "SOA") {
                                        record["txtdata"] = [];
                                        record.data_b64.forEach(function(data) {
                                            record.txtdata.push(BASE64.decodeUTF8(data));
                                        });
                                        store.zone_serial_number = record.txtdata[2];
                                    }
                                } else if (record.type === "control") {
                                    defaultTTL = BASE64.decodeUTF8(record.text_b64);
                                    defaultTTL = defaultTTL.split(" ");
                                    defaultTTL = defaultTTL[1];
                                    store.zoneDefaultTTL = parseInt(defaultTTL, 10);
                                }
                            }

                            return {
                                parsedZoneData: parsedData,
                                defaultTTL: defaultTTL,
                            };
                        } else {
                            return $q.reject(parsedResponse);
                        }
                    })
                    .catch(function(response) {
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return $q.reject(store.request_failure_message(response.status));
                    });
            };

            function _remove_zone_record(zone, line, serial) {
                var apiCall = new UAPIREQUEST.Class();
                apiCall.initialize("DNS", "mass_edit_zone");
                apiCall.addArgument("zone", zone);
                apiCall.addArgument("serial", serial);
                apiCall.addArgument("remove", line);

                return store._promise(apiCall)
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            return true;
                        } else {
                            return $q.reject(response);
                        }
                    })
                    .catch(function(response) {
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return $q.reject(store.request_failure_message(response.status));
                    });
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
            store.remove_zone_record = function(zone, line) {
                return _remove_zone_record(zone, line, store.zone_serial_number);

            };

            store.reset_zone = function(domain) {
                var apiCall = new API2REQUEST.Class();
                apiCall.initialize("ZoneEdit", "resetzone");
                apiCall.addArgument("domain", domain);

                return store._promise(apiCall)
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            return true;
                        } else {
                            return $q.reject(response);
                        }
                    })
                    .catch(function(response) {
                        if (!response.status) {
                            return $q.reject(response.error);
                        }
                        return $q.reject(store.request_failure_message(response.status));
                    });
            };

            function flatten_array_to_object(array, key) {
                var obj = {};
                for (var i = 0, len = array.length; i < len; i++) {
                    if (array[i][key] && array[i][key].length > 0) {
                        obj[array[i][key]] = true;
                    }
                }
                return obj;
            }

            store.fetch_generated_domains = function(domain, force) {
                if (_.keys(store.generated_domains).length === 0 || force) {
                    var apiCall = new API2REQUEST.Class();
                    apiCall.initialize("ZoneEdit", "fetch_cpanel_generated_domains");
                    apiCall.addArgument("domain", domain);
                    return store._promise(apiCall)
                        .then(function(response) {
                            response = response.parsedResponse;
                            store.generated_domains = flatten_array_to_object(response.data, "domain");
                            return store.generated_domains;
                        })
                        .catch(function(err) {
                            return $q.reject(store.request_failure_message(err.status));
                        });
                } else {
                    return $q.when(store.generated_domains);
                }
            };

            store.format_zone_name = function(domain, zone_name) {
                var name = zone_name;
                if (!angular.isDefined(name) || name === null || name === "") {
                    return "";
                }

                // add a dot at the end of the name, if needed
                if (zone_name.charAt(zone_name.length - 1) !== ".") {
                    name += ".";
                }

                // return what we have if a domain is not specified
                if (!angular.isDefined(domain) || domain === null || domain === "") {
                    return name;
                }

                // add the domain, if it does not already exist
                var domain_part = domain + ".";
                var end_of_zone_name = name.slice(domain_part.length * -1);
                if (end_of_zone_name.toLowerCase() !== domain_part.toLowerCase()) {
                    name += domain_part;
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
        }]);

        return factory;
    }
);
