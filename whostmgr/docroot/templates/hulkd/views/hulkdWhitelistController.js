/*
# cpanel - whostmgr/docroot/templates/hulkd/views/hulkdWhitelistController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint camelcase: 0, no-prototype-builtins: 0 */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "app/utils/download",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/decorators/growlDecorator",
        "cjt/filters/startFromFilter",
        "app/services/HulkdDataSource",
    ],
    function(angular, $, _, LOCALE, Download) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("App");
        app.config([ "$compileProvider",
            function($compileProvider) {
                $compileProvider.aHrefSanitizationWhitelist(/^blob:https:/);
            },
        ]);

        var controller = app.controller(
            "hulkdWhitelistController",
            ["$rootScope", "$scope", "$filter", "$routeParams", "$uibModal", "HulkdDataSource", "growl", "PAGE", "growlMessages", "$timeout",
                function($rootScope, $scope, $filter, $routeParams, $uibModal, HulkdDataSource, growl, PAGE, growlMessages, $timeout) {

                    $scope.whitelist_reverse = false;

                    $scope.whitelist = [];
                    $scope.whitelist_comments = {};

                    $scope.adding_batch_to_whitelist = false;

                    $scope.new_whitelist_records = "";

                    $scope.ip_being_edited = false;
                    $scope.current_ip = null;
                    $scope.current_comment = "";
                    $scope.updating_comment = false;

                    $scope.modal_instance = null;

                    $scope.loading = false;

                    $scope.downloadAllLink = "";
                    $scope.downloadSelectionLink = "";

                    $scope.meta = {
                        sortDirection: "asc",
                        sortBy: "white_ip",
                        sortType: "",
                        sortReverse: false,
                        filter: "",
                        maxPages: 0,
                        totalItems: $scope.whitelist.length || 0,
                        currentPage: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100],
                    };

                    $scope.LOCALE = LOCALE;

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo"),
                    };

                    $scope.delete_in_progress = false;
                    $scope.ips_to_delete = [];

                    // Handle auto-adding an ip from a query param or POST
                    if (($routeParams["ip"] && $routeParams["ip"].length > 0) ||
                        PAGE.ipToAdd !== null) {
                        var ip;
                        var comment = "";

                        if ($routeParams["ip"] && $routeParams["ip"].length > 0) {

                            // added via a query param
                            ip = $routeParams["ip"];
                        } else if (PAGE.ipToAdd !== null) {

                            // added via a POST and stuffed into PAGE
                            ip = PAGE.ipToAdd;
                        }

                        // clear the ip so we don't add it again
                        PAGE.ipToAdd = null;

                        if (ip !== void 0) {
                            $scope._add_to_whitelist([ { ip: ip, comment: comment } ]);
                        }
                    }


                    $scope.growl_whitelist_warning = function(missing_ip) {

                        // create a new growl to be displayed.
                        var message_cache = LOCALE.maketext("Your current IP address “[_1]” is not on the whitelist.", _.escape(missing_ip));
                        $rootScope.whitelist_warning_message = growl.error(message_cache,
                            {
                                variables: {
                                    buttonLabel: LOCALE.maketext("Add to Whitelist"),
                                    showAction: true,
                                    action: function() {
                                        $rootScope.one_click_add_to_whitelist(missing_ip)
                                            .then(function() {
                                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                            });
                                    },
                                },
                                onclose: function() {
                                    $rootScope.whitelist_warning_message = null;
                                },
                            }
                        );
                    };

                    $scope.edit_whitelist_ip = function(whitelist_ip) {
                        $scope.current_ip = whitelist_ip;
                        $scope.current_comment = $scope.whitelist_comments.hasOwnProperty(whitelist_ip) ? $scope.whitelist_comments[whitelist_ip] : "";
                        $scope.ip_being_edited = true;
                        var whitelist_comment_field = $("#whitelist_current_comment");
                        var wait_id = setInterval( function() {
                            if (whitelist_comment_field.is(":visible")) {
                                whitelist_comment_field.focus();
                                whitelist_comment_field.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    $scope.cancel_whitelist_editing = function() {
                        $scope.current_ip = null;
                        $scope.current_comment = "";
                        $scope.ip_being_edited = false;
                        $scope.focus_on_whitelist();
                    };

                    $scope.delete_tooltip = function(ip_address) {
                        return LOCALE.maketext("Click to delete “[_1]” from the whitelist.", ip_address);
                    };

                    $scope.edit_tooltip = function(ip_address) {
                        return LOCALE.maketext("Click to edit the comment for “[_1]”.", ip_address);
                    };

                    $scope.update_whitelist_comment = function() {
                        if ($scope.updating_comment) {
                            return;
                        }

                        $scope.updating_comment = true;
                        HulkdDataSource.add_to_whitelist([ { ip: $scope.current_ip, comment: $scope.current_comment } ])
                            .then( function(results) {
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;

                                // Growl out each success from the batch.
                                results.updated.forEach(function(ip) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(ip)));
                                });

                                // Report the failures from the batch.
                                var rejectedMessages = [];
                                Object.keys(results.rejected).forEach(function(ip) {
                                    rejectedMessages.push(_.escape(ip) + ": " + _.escape(results.rejected[ip]));
                                });

                                if (rejectedMessages.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some records failed to update.") + "<br>";
                                    accumulatedMessages += rejectedMessages.join("<br>");
                                    growl.error(accumulatedMessages);
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updating_comment = false;
                                $scope.cancel_whitelist_editing();
                                $scope.focus_on_whitelist();
                            });
                    };

                    var ipV6 = /^(([\da-fA-F]{1,4}:){4})(([\da-fA-F]{1,4}:){3})([\da-fA-F]{1,4})$/;
                    var ipV4Range = /^((\d{1,3}.){3}\d{1,3})-((\d{1,3}.){3}\d{1,3})$/;
                    var ipRangeTest = /-/;
                    var ipV6Test = /:/;

                    /**
                     * Separates long ipv4 and ipv6 addresses with br tags.
                     * Also, supports separating ipv4 and ipv6 address ranges.
                     *
                     * @param {string} ip - an ip address
                     * @todo Implement this as an Angular Filter in a separate file
                     */
                    $scope.splitLongIp = function(ip) {

                        // ipv6?
                        if (ipV6Test.test(ip)) {

                            // is this a range?
                            if (ipRangeTest.test(ip)) {

                                // format the ipv6 addresses in range format
                                var ipv6Addresses = ip.split(ipRangeTest);
                                var ipv6AddressRange = "";

                                // get the first part of the range
                                var match = ipV6.exec(ipv6Addresses[0]);
                                if (match) {
                                    ipv6AddressRange += match[1] + "<br>" + match[3] + match[5];
                                }

                                // add the range separator
                                ipv6AddressRange += "-<br>";

                                // get the second part of the range
                                match = ipV6.exec(ipv6Addresses[1]);
                                if (match) {
                                    ipv6AddressRange += match[1] + "<br>" + match[3] + match[5];
                                }

                                // if all we have is -<br>, then forget it
                                if (ipv6AddressRange.length > 5) {
                                    return ipv6AddressRange;
                                }
                            } else {

                                // format the ipv6 address
                                var v6match = ipV6.exec(ip);
                                if (v6match) {
                                    return v6match[1] + "<br>" + v6match[3] + v6match[5];
                                }
                            }
                        } else {

                            // format the ipv4 range
                            var v4rangeMatch = ipV4Range.exec(ip);
                            if (v4rangeMatch) {
                                return v4rangeMatch[1] + "-<br>" + v4rangeMatch[3];
                            }
                        }

                        // could not format it, just return it
                        return ip;
                    };

                    $scope.$watch(function() {
                        return HulkdDataSource.enabled;
                    }, function() {
                        $scope.load_list();
                    });

                    $scope.$watch(function() {
                        return $rootScope.ip_added_with_one_click === true;
                    }, function() {
                        $scope.applyFilters();
                        $rootScope.ip_added_with_one_click = false;
                    });

                    $scope.$watchGroup([ "whitelist.length", "meta.filteredList.length" ], function() {
                        if ($scope.whitelist.length === 0 || $scope.meta.filteredList.length === 0) {
                            $("#whitelist_select_all_checkbox").prop("checked", false);
                        }
                    });

                    $scope.selectPage = function(page) {
                        $("#whitelist_select_all_checkbox").prop("checked", false);

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.currentPage = page;
                        }

                        $scope.load_list();
                    };

                    $scope.selectPageSize = function() {
                        return $scope.load_list({ reset_focus: false });
                    };

                    /**
                     * Filter the list by the `meta.filter`.
                     */
                    $scope.filterList = function() {
                        $scope.meta.currentPage = 1;
                        $scope.load_list({ reset_focus: false });
                    };

                    /**
                     * Clear the filter if it is set.
                     */
                    $scope.toggleFilter = function() {
                        $scope.meta.filter = "";
                        $scope.load_list({ reset_focus: false });
                    };

                    $scope.sortList = function(meta) {
                        $scope.meta.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        $scope.applyFilters();
                    };

                    $scope.orderByComments = function(comment_object, ip_list) {
                        var comments_as_pairs = _.toPairs(comment_object);
                        var ips_as_pairs = [];

                        // get the IPs that have no comments
                        for (var i = 0; i < ip_list.length; i++) {
                            if (!_.has(comment_object, ip_list[i] )) {
                                var one_entry = [ip_list[i], "" ];
                                ips_as_pairs.push(one_entry);
                            }
                        }

                        // sort the IPs that have no comments
                        var sorted_pairs = _.sortBy(ips_as_pairs, function(pair) {
                            return $scope.ip_padder(pair[0]);
                        });

                        // sort the comments first by comment, then by IP address
                        comments_as_pairs.sort(compareComments);

                        // create an array of the IPs from the sorted comments
                        var just_ips_comments = _.map(comments_as_pairs, function(pair) {
                            return pair[0];
                        });

                        // create an array of the sorted IPs with no comments
                        var just_ips = _.map(sorted_pairs, function(pair) {
                            return pair[0];
                        });

                        // put the IPs with comments and the IPs without comments together
                        var stuck_together = just_ips_comments.concat(just_ips);

                        if ($scope.meta.sortDirection === "desc") {
                            return stuck_together.reverse();
                        }

                        return stuck_together;
                    };

                    /**
                     * Apply the sort, filter and pagination to the whitelist data.
                     *
                     * @returns {string[]} List of ips that pass the filters.
                     */
                    $scope.applyFilters = function() {
                        var filteredList = [];
                        var start, limit;

                        filteredList = $scope.whitelist;

                        // Sort
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            if ($scope.meta.sortBy === "white_ip") {
                                filteredList = filters.orderBy(filteredList, $scope.ip_padder, $scope.meta.sortReverse);
                            } else {
                                filteredList = $scope.orderByComments($scope.whitelist_comments, $scope.whitelist);
                            }
                        }

                        // Totals
                        $scope.meta.totalItems = $scope.whitelist.length;

                        // Filter content
                        var expected = $scope.meta.filter.toLowerCase();
                        if (expected) {
                            filteredList = filters.filter(filteredList, function(actual) {
                                return actual.indexOf(expected) !== -1 ||
                                       ($scope.whitelist_comments[actual] && $scope.whitelist_comments[actual].toLowerCase().indexOf(expected) !== -1);
                            });
                        }

                        // Track the filtered size separatly
                        $scope.meta.filteredItems = filteredList.length;

                        // Pagination
                        start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                        limit = $scope.meta.pageSize;
                        filteredList = filters.limitTo(filters.startFrom(filteredList, start), limit);

                        $scope.meta.pageNumberStart = start + 1;
                        $scope.meta.pageNumberEnd = ($scope.meta.currentPage * $scope.meta.pageSize);

                        if ($scope.meta.totalItems === 0) {
                            $scope.meta.pageNumberStart = 0;
                        }

                        if ($scope.meta.pageNumberEnd > $scope.meta.totalItems) {
                            $scope.meta.pageNumberEnd = $scope.meta.totalItems;
                        }

                        $scope.meta.filteredList = filteredList;

                        return filteredList;
                    };

                    $scope.load_list = function(options) {
                        if (HulkdDataSource.enabled && !$scope.loading) {

                            $scope.loading = true;
                            var reset_focus = typeof options !== "undefined" && options.hasOwnProperty("reset_focus") ? options.reset_focus : true;

                            if (HulkdDataSource.whitelist_is_cached) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                $scope.applyFilters();
                                if (reset_focus) {
                                    $scope.focus_on_whitelist();
                                }
                                $scope.loading = false;
                            } else {
                                $scope.meta.filteredList = [];
                                return HulkdDataSource.load_list("white")
                                    .then(function(results) {
                                        $scope.whitelist = HulkdDataSource.whitelist;
                                        $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                        $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                        $scope.applyFilters();

                                        // if the requester ip is not whitelisted and the growl does not exist or is not displayed, then display it
                                        if (results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted <= 0) {
                                            if (results.hasOwnProperty("requester_ip") && $rootScope.whitelist_warning_message === null) {
                                                $scope.growl_whitelist_warning(results.requester_ip);
                                            }
                                        }

                                        if (results.restart_ssh) {
                                            growl.warning(LOCALE.maketext("The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.", PAGE.security_token + "/scripts/ressshd", { "target": "_blank" }));
                                        } else if (results.warning_ssh) {
                                            growl.warning(results.warning_ssh);
                                        }
                                    }, function(error) {
                                        growl.error(error);
                                    })
                                    .finally(function() {
                                        if (reset_focus) {
                                            $scope.focus_on_whitelist();
                                        }
                                        $scope.loading = false;
                                    });
                            }
                        }
                        return null;
                    };

                    $scope.force_load_whitelist = function() {
                        HulkdDataSource.whitelist_is_cached = false;
                        $scope.whitelist = [];
                        $scope.whitelist_comments = {};
                        $scope.meta.filteredList = [];
                        return $scope.load_list();
                    };

                    $scope.delete_confirmation_message = function() {
                        if ($scope.ips_to_delete.length === 1) {
                            return LOCALE.maketext("Do you want to permanently delete “[_1]” from the whitelist?", $scope.ips_to_delete[0]);
                        } else {
                            return LOCALE.maketext("Do you want to permanently delete [quant,_1,record,records] from the whitelist?", $scope.ips_to_delete.length);
                        }
                    };

                    $scope.itemsAreChecked = function() {
                        return $(".whitelist_select_item").filter(":checked").length > 0;
                    };

                    $scope.check_whitelist_selection = function() {
                        if ($(".whitelist_select_item").filter(":not(:checked)").length === 0) {
                            $("#whitelist_select_all_checkbox").prop("checked", true);
                        } else {
                            $("#whitelist_select_all_checkbox").prop("checked", false);
                        }
                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                    };

                    /**
                     * Get the list of ips selected in the UI.
                     *
                     * @returns <string[]> List if ips selected.
                     */
                    $scope.getSelection = function()  {
                        var selected_items = [],
                            $selected_dom_nodes = $(".whitelist_select_item:checked");

                        if ($selected_dom_nodes.length === 0) {
                            return [];
                        }

                        $selected_dom_nodes.each( function() {
                            selected_items.push($(this).data("ip"));
                        });

                        return selected_items;
                    };

                    $scope.confirm_whitelist_deletion = function(ip_to_delete) {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $scope.delete_in_progress = true;
                        if (ip_to_delete !== undefined) {
                            $scope.ips_to_delete = [ip_to_delete];
                            $scope.is_single_deletion = true;
                        } else {
                            var selected_items = $scope.getSelection();
                            if (selected_items.length === 0) {
                                return false;
                            }
                            $scope.ips_to_delete = selected_items;
                            $scope.is_single_deletion = false;
                        }

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_whitelist_deletion.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.clear_modal_instance = function() {
                        if ($scope.modal_instance) {
                            $scope.modal_instance.close();
                            $scope.modal_instance = null;
                        }
                    };

                    $scope.cancel_deletion = function() {
                        $scope.delete_in_progress = false;
                        $scope.ips_to_delete = [];
                        $scope.clear_modal_instance();
                        $scope.focus_on_whitelist();
                    };

                    $scope.delete_whitelist_ips = function(is_single_deletion) {
                        $scope.clear_modal_instance();
                        HulkdDataSource.remove_from_whitelist($scope.ips_to_delete)
                            .then( function(results) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.applyFilters();
                                $scope.focus_on_whitelist();

                                if (results.removed.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully deleted “[_1]” from the whitelist.", _.escape(results.removed[0])));
                                } else {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the whitelist.", results.removed.length));
                                }

                                if ( results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted <= 0 && results.hasOwnProperty("requester_ip") ) {
                                    $scope.growl_whitelist_warning(results.requester_ip);
                                }

                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the whitelist.", results.not_removed.keys.length));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.ips_to_delete = [];
                                if (!is_single_deletion) {
                                    $scope.deselect_all_whitelist();
                                }

                                // Since this is using JQuery/DOM, we have to wait another tick for the UI to update
                                // before we try to get the selection.
                                $timeout(function() {
                                    $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                    $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                                });
                            });
                    };

                    $scope.confirm_delete_all = function() {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $scope.delete_in_progress = true;

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_whitelist_delete_all.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.cancel_delete_all = function() {
                        $scope.delete_in_progress = false;
                        $scope.clear_modal_instance();
                        $scope.focus_on_whitelist();
                    };

                    $scope.delete_all = function() {
                        $scope.clear_modal_instance();
                        HulkdDataSource.remove_all_from_whitelist()
                            .then( function(results) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.applyFilters();
                                $scope.focus_on_whitelist();
                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the whitelist.", results.removed.keys.length));
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the whitelist.", results.not_removed.keys.length));
                                } else {
                                    growl.success(LOCALE.maketext("You have deleted all records from the whitelist."));
                                }

                                if ( results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted <= 0 && results.hasOwnProperty("requester_ip") ) {
                                    $scope.growl_whitelist_warning(results.requester_ip);
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.deselect_all_whitelist();

                                // Since this is using JQuery/DOM, we have to wait another tick for the UI to update
                                // before we try to get the selection.
                                $timeout(function() {
                                    $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                    $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                                });
                            });
                    };

                    $scope.select_all_whitelist = function() {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $(".whitelist_select_item").prop("checked", true);
                        $("#whitelist_select_all_checkbox").prop("checked", true);

                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();

                        return true;
                    };

                    $scope.deselect_all_whitelist = function() {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $(".whitelist_select_item").prop("checked", false);
                        $("#whitelist_select_all_checkbox").prop("checked", false);

                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();

                        return true;
                    };

                    $scope.toggle_whitelist_selection = function() {
                        if ($("#whitelist_select_all_checkbox").prop("checked") === true) {
                            $scope.select_all_whitelist();
                        } else {
                            $scope.deselect_all_whitelist();
                        }
                    };

                    $scope.focus_on_whitelist = function() {
                        var whitelist_batch_field = $("#whitelist_batch_add");
                        var wait_id = setInterval( function() {
                            if (whitelist_batch_field.is(":visible")) {
                                whitelist_batch_field.focus();
                                whitelist_batch_field.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    /**
                     *
                     * @typedef Record
                     * @property {string} ip
                     * @property {string?} comment
                     */

                    /**
                     * Parse the batch of records.
                     *
                     * @param {string} text
                     * @returns {Record[]}
                     */
                    function parseBatch(text) {
                        var lines = text.split("\n");
                        var records = [];

                        for (var i = 0; i < lines.length; i++) {
                            var line = lines[i];
                            if (line && line.length > 0) {
                                var parts = line.split("#");
                                var ip = parts.shift().trim();
                                var comment = parts.join("#").trim();
                                records.push({
                                    ip: ip,
                                    comment: comment,
                                });
                            }
                        }
                        return records;
                    }

                    /**
                     * Add a batch of records to the whitelist.
                     *
                     * @async
                     * @returns
                     */
                    $scope.add_to_whitelist = function() {
                        if (!$scope.new_whitelist_records || $scope.adding_batch_to_whitelist) {
                            return;
                        }

                        var records = parseBatch($scope.new_whitelist_records);
                        return $scope._add_to_whitelist(records);
                    };

                    /**
                     * Add a batch of whitelist records.
                     *
                     * @private
                     * @param {Record[]} batch
                     * @returns
                     */
                    $scope._add_to_whitelist = function(batch) {
                        $scope.adding_batch_to_whitelist = true;
                        return HulkdDataSource.add_to_whitelist(batch)
                            .then( function(results) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                $scope.applyFilters();

                                if (results.added.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully added “[_1]” to the whitelist.", _.escape(results.added[0])));
                                } else if (results.added.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully added [quant,_1,IP address,IP addresses] to the whitelist.", results.added.length));
                                }

                                if (results.updated.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(results.updated[0])));
                                } else if (results.updated.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully updated the [numerate,_1,comment,comments] for [quant,_1,IP address,IP addresses].", results.updated.length));
                                }

                                // if requester ip is marked as being whitelisted in the last call, but the growl warning
                                // is still displayed then hide the growl warning
                                if (results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted > 0 && $rootScope.whitelist_warning_message !== null) {
                                    $rootScope.whitelist_warning_message.ttl = 0;
                                    $rootScope.whitelist_warning_message.promises = [];
                                    $rootScope.whitelist_warning_message.promises.push($timeout(angular.bind(growlMessages, function() {
                                        growlMessages.deleteMessage($rootScope.whitelist_warning_message);
                                        $rootScope.whitelist_warning_message = null;
                                    }), 200));
                                }

                                var rejectedIps = Object.keys(results.rejected);
                                if (rejectedIps.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some IP addresses were not added to the whitelist.");
                                    accumulatedMessages += "<br>\n";

                                    // Put the rejected ips/comments back in the list.
                                    $scope.new_whitelist_records = rejectedIps.map(function(ip) {
                                        var record = batch.find(function(record) {
                                            return record.ip === ip;
                                        });
                                        if (record && record.comment) {
                                            return ip + " # " + record.comment + "\n";
                                        }
                                        return ip + "\n";
                                    }).join("");

                                    // Report the problems in the growl
                                    accumulatedMessages += "<ul>\n";
                                    rejectedIps.forEach(function(ip) {
                                        if (results.rejected[ip]) {
                                            accumulatedMessages += "<li>" + _.escape(results.rejected[ip]) + "</li>\n";
                                        }
                                    });
                                    accumulatedMessages += "</ul>\n";
                                    growl.error(accumulatedMessages);

                                } else {
                                    $scope.new_whitelist_records = "";
                                }
                            }, function(error_details) {
                                var error = error_details.main_message;

                                // Format the individual partial errors.
                                var secondary_count = error_details.secondary_messages.length;
                                if (secondary_count > 0) {
                                    error += "<ul>\n";
                                }

                                error_details.secondary_messages.forEach(function(message) {
                                    error += "<li>" + _.escape(message) + "</li>\n";
                                });

                                if (secondary_count > 0) {
                                    error += "</ul>\n";
                                }

                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.adding_batch_to_whitelist = false;
                                $scope.focus_on_whitelist();
                            });
                    };

                    // TODO: Make this a utility system: ip-comparison
                    $scope.ip_padder = function(unpadded) {
                        var padded_ip = "";
                        if (unpadded) {
                            var split_ip = unpadded.split(".");
                            for (var i = 0; i < split_ip.length; i++) {
                                var this_section = split_ip[i];
                                while ( this_section.length < 3) {
                                    this_section = "0" + this_section;
                                }
                                padded_ip += this_section;
                            }
                        }
                        return padded_ip;
                    };

                    function compareComments(a, b) {

                        // sort by comment
                        if (a[1].toLowerCase() < b[1].toLowerCase()) {
                            return -1;
                        }
                        if (a[1].toLowerCase() > b[1].toLowerCase()) {
                            return 1;
                        }

                        // we have a duplicate comment, so sort by IP address
                        if ($scope.ip_padder(a[0]) < $scope.ip_padder(b[0])) {
                            return -1;
                        }
                        if ($scope.ip_padder(a[0]) > $scope.ip_padder(b[0])) {
                            return 1;
                        }

                        // we have a duplicate comment and IP
                        return 0;
                    }

                    /**
                     * Generate the download name.
                     *
                     * @returns {string} - the name of the download.
                     */
                    $scope.downloadName = function() {
                        return Download.getDownloadName("whitelist");
                    };

                    /**
                     * @typedef IpRecord
                     * @property {string} ip - ip address or range.
                     * @property {string?} comment - comment associated with the ip or range.
                     */

                    /**
                     * Package the ips and comments into a records structure
                     *
                     * @param {string[]} ips
                     * @param {Dictionary<string,string>} comments
                     * @returns {IpRecord[]}
                     */
                    function getRecords(ips, comments) {
                        var list = [];
                        ips.forEach(function(ip) {
                            var comment = comments[ip];
                            list.push({ ip: ip, comment: comment });
                        });
                        return list;
                    }

                    /**
                     * Generate a data blob url that contains all the whitelist ips.
                     *
                     * @returns {string} - data url.
                     */
                    $scope.generateDownloadAllLink = function() {

                        if ($scope.downloadAllLink) {

                            // Clean up the previous url
                            Download.cleanupDownloadUrl($scope.downloadAllLink);
                            $scope.downloadAllLink = null;
                        }

                        var ips = $scope.whitelist;
                        if (!ips || ips.length === 0) {
                            return "";
                        }

                        var list = getRecords(ips, $scope.whitelist_comments);
                        return Download.getTextDownloadUrl(Download.formatList(list));
                    };

                    /**
                     * Generate a data blob url that contains the selected whitelist ips.
                     *
                     * @returns {string} - data url.
                     */
                    $scope.generateDownloadSelectionLink = function() {
                        if ($scope.downloadSelectionLink) {

                            // Clean up the previous url
                            Download.cleanupDownloadUrl($scope.downloadSelectionLink);
                            $scope.downloadSelectionLink = null;
                        }

                        if (!$scope.whitelist || $scope.whitelist.length === 0) {
                            return "";
                        }

                        var selection = $scope.getSelection();
                        if (!selection || selection.length === 0) {
                            return "";
                        }

                        var list = getRecords(selection, $scope.whitelist_comments);

                        return Download.getTextDownloadUrl(Download.formatList(list));
                    };

                    $scope.focus_on_whitelist();
                },
            ]);

        return controller;
    }
);
