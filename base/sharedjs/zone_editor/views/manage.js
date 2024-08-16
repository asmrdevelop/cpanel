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
    [
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
