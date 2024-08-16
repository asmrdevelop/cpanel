/*
# services/recordTypes.js                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "app/services/features",
        "cjt/io/uapi-request",
        "cjt/modules",
        "cjt/io/api",
        "cjt/io/uapi",
    ],
    function(angular, _, FeaturesService) {

        "use strict";

        var MODULE_NAMESPACE = "cpanel.zoneEditor.services.recordTypes";
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
