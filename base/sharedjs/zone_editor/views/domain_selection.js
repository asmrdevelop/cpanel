/*
# zone_editor/views/domain_selection.js              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/* jshint -W100 */

define(
    [
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
