/*
# convert_addon_to_account/views/history.js       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* eslint camelcase: "off" */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/models/dynamic_table",
        "app/services/conversion_history",
        "app/filters/local_datetime_filter",
        "app/directives/job_status",
        "cjt/decorators/growlDecorator",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective"
    ],
    function(angular, _, LOCALE, DynamicTable, ConversionHistory) {
        "use strict";

        var app = angular.module("App");

        var controller = app.controller(
            "historyController",
            ["$location", "growl", "ConversionHistory", "$timeout", "$scope",
                function($location, growl, ConversionHistory, $timeout, $scope) {
                    var history_vm = this;

                    history_vm.ui = {};
                    history_vm.ui.is_loading = false;
                    history_vm.in_progress = {};
                    history_vm.in_progress_timer = null;

                    var conversion_table = new DynamicTable();
                    conversion_table.setSort("start_time");

                    function searchConversionsFunction(item, searchText) {
                        return item.domain.indexOf(searchText) !== -1;
                    }
                    conversion_table.setFilterFunction(searchConversionsFunction);

                    history_vm.conversions = {
                        "meta": conversion_table.getMetadata(),
                        "filteredList": conversion_table.getList(),
                        "paginationMessage": conversion_table.paginationMessage,
                        "fetch": function() {
                            history_vm.conversions.filteredList = conversion_table.populate();
                        },
                        "sortList": function() {
                            history_vm.conversions.fetch();
                        },
                        "selectPage": function() {
                            history_vm.conversions.fetch();
                        },
                        "selectPageSize": function() {
                            history_vm.conversions.fetch();
                        },
                        "searchList": function() {
                            history_vm.conversions.fetch();
                        }
                    };

                    history.clearSearch = function(event) {
                        if (event.keyCode === 27) {
                            history.conversions.meta.filterValue = "";
                            history.conversions.searchList();
                        }
                    };

                    // sort the status in descending order to make the
                    // most recent ones show at the top
                    history_vm.conversions.meta.sortDirection = "desc";

                    history_vm.updateStatusFor = function(job_ids) {
                        return ConversionHistory.getJobStatus(job_ids)
                            .then(function(data) {
                                for (var job in data) {
                                    if (history_vm.in_progress[job] !== void 0 &&
                                    data[job].job_status !== history_vm.in_progress[job].status) {
                                        history_vm.in_progress[job].status = data[job].job_status;

                                        if (data[job].job_status !== "INPROGRESS") {
                                            history_vm.in_progress[job].end_time = data[job].job_end_time;
                                            var this_domain = history_vm.in_progress[job].domain;
                                            if (data[job].job_status === "FAILED") {
                                                growl.error(LOCALE.maketext("The conversion of the domain “[_1]” failed.", _.escape(this_domain)));
                                            } else {
                                                growl.info(LOCALE.maketext("The conversion of the domain “[_1]” succeeded.", _.escape(this_domain)));
                                            }
                                            delete history_vm.in_progress[job];
                                        }
                                    }
                                }

                                if (Object.keys(history_vm.in_progress).length !== 0) {
                                    history_vm.in_progress_timer = $timeout(function() {
                                        history_vm.updateStatusFor(job_ids);
                                    }, 1000);
                                }
                            });
                    };

                    history_vm.goToDetailsView = function(job_id) {
                        return $location.path("/history/" + job_id + "/detail");
                    };

                    history_vm.viewAddons = function() {
                        $location.path("/main");
                    };

                    history_vm.init = function() {
                        history_vm.ui.is_loading = true;

                        ConversionHistory.load()
                            .then(function(data) {
                                conversion_table.loadData(data);
                                history_vm.conversions.fetch();

                                // iterate through the list of
                                // jobs and find the ones that are
                                // in progress
                                var totalJobs = data.length;
                                var i = 0;

                                for (; i < totalJobs; i++) {
                                    if (data[i].status === "INPROGRESS") {
                                        history_vm.in_progress[data[i].job_id] = data[i];
                                    }
                                }

                                var job_ids = Object.keys(history_vm.in_progress);

                                if (job_ids.length > 0) {
                                /* jshint -W083 */
                                    history_vm.in_progress_timer = $timeout( function() {
                                        history_vm.updateStatusFor(job_ids);
                                    }, 1000);
                                /* jshint +W083 */
                                }

                            })
                            .catch(function(meta) {
                                growl.error(meta.reason);
                            })
                            .finally(function() {
                                history_vm.ui.is_loading = false;
                            });
                    };

                    history_vm.clearInProgress = function() {
                        if (history_vm.in_progress_timer) {
                            $timeout.cancel(history_vm.in_progress_timer);
                            history_vm.in_progress_timer = null;
                        }
                        history_vm.in_progress = {};
                    };

                    history_vm.forceLoadList = function() {
                        conversion_table.clear();
                        history_vm.clearInProgress();
                        history_vm.init();
                    };

                    $scope.$on("$destroy", function() {
                        history_vm.clearInProgress();
                    });

                    history_vm.init();
                }
            ]);

        return controller;
    }
);
