/*
# templates/greylist/views/trustedHosts.js               Copyright(c) 2020 cPanel, L.L.C.
#                                                                  All rights reserved.
# copyright@cpanel.net                                                http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "app/util/ipPadder",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/decorators/growlDecorator",
        "cjt/filters/startFromFilter",
        "app/services/GreylistDataSource"
    ],
    function(angular, $, _, LOCALE, ipPad) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "trustedHostsController",
            ["$scope", "$rootScope", "$filter", "$uibModal", "GreylistDataSource", "growl",
                function($scope, $rootScope, $filter, $uibModal, GreylistDataSource, growl) {

                    $scope.trustedHosts = GreylistDataSource.trustedHosts;
                    $scope.ips_to_delete = [];
                    $scope.netblock = [];
                    $scope.netblockTrusted = false;
                    $scope.newTrustedHosts = "";
                    $scope.newTrustedHostComment = "";

                    $scope.current_ip = null;
                    $scope.current_comment = "";

                    $scope.modal_instance = null;

                    $scope.addingBatchToTrustedHosts = false;
                    $scope.delete_in_progress = false;
                    $scope.ip_being_edited = false;
                    $scope.list_loading = false;
                    $scope.selectAllCheckbox = false;
                    $scope.selecting_page_size = false;
                    $scope.trustedHostsReverse = false;
                    $scope.updating_comment = false;

                    $scope.ipAddressExampleText = "<strong>" + LOCALE.maketext("Examples:") + "</strong><br>169.254.1.1<br>169.254.1.10-169.254.1.10<br>169.254.0.0/16<br>2001:db8::<br>2001:db8::-2001:db8:ffff:ffff:ffff:ffff:ffff:ffff<br>2001:db8::/32";

                    $scope.meta = {
                        sortDirection: "asc",
                        sortBy: "hostIp",
                        sortType: "",
                        sortReverse: false,
                        maxPages: 0,
                        totalRows: $scope.trustedHosts.length || 0,
                        pageNumber: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100]
                    };

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo")
                    };

                    $scope.editTrustedHost = function(trustedHost) {
                        $scope.current_ip = trustedHost.host_ip;
                        $scope.current_comment = trustedHost.comment;
                        $scope.ip_being_edited = true;
                        var trustedHostCommentField = $("#currentTrustedHostComment");
                        var wait_id = setInterval( function() {
                            if (trustedHostCommentField.is(":visible")) {
                                trustedHostCommentField.focus();

                                // WebKit doesn't always select empty fields correctly
                                if ($scope.current_comment === "") {
                                    var commentField = document.getElementById("currentTrustedHostComment");
                                    commentField.innerHTML = "";
                                    if (commentField.setSelectionRange) {
                                        commentField.setSelectionRange(0, 1);
                                    }
                                }
                                trustedHostCommentField.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    $scope.cancelTrustedHostEditing = function() {
                        $scope.current_ip = null;
                        $scope.current_comment = "";
                        $scope.ip_being_edited = false;
                        $scope.focusOnListEditor();
                    };

                    $scope.deleteTooltip = function(ipAddress) {
                        return LOCALE.maketext("Click to delete “[_1]” from the Trusted Hosts list.", ipAddress);
                    };

                    $scope.editTooltip = function(ipAddress) {
                        return LOCALE.maketext("Click to edit the comment for “[_1]”.", ipAddress);
                    };

                    $scope.itemsAreChecked = function() {
                        return $(".selectItem").filter(":checked").length > 0;
                    };

                    $scope.checkSelection = function() {
                        if ($(".selectItem").filter(":not(:checked)").length === 0) {
                            $scope.selectAllCheckbox = true;
                        } else {
                            $scope.selectAllCheckbox = false;
                        }
                    };

                    $scope.toggleSelection = function(selectAll) {
                        if (selectAll) {
                            $scope.selectAll();
                        } else {
                            $scope.deselectAll();
                        }
                    };

                    $scope.changePageSize = function() {
                        return $scope.loadList({ reset_focus: false });
                    };

                    $scope.fetchPage = function(page) {
                        $scope.selectAllCheckbox = false;

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.pageNumber = page;
                        }
                        return $scope.loadList();
                    };

                    $scope.sortList = function(meta) {
                        $scope.deselectAll();
                        $scope.meta.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        $scope.filteredList();
                    };

                    $scope.orderByComments = function() {
                        var checkForComment = function(trustedHost) {
                            return trustedHost.comment !== "";
                        };

                        var ipsWithComments = _.filter($scope.trustedHosts, checkForComment);
                        var ipsNoComments = _.reject($scope.trustedHosts, checkForComment);

                        ipsWithComments = _.sortBy(ipsWithComments, function(trustedHost) {
                            return trustedHost.comment;
                        });
                        ipsNoComments = _.sortBy(ipsNoComments, function(trustedHost) {
                            return trustedHost.host_ip;
                        });

                        var stuck_together = ipsWithComments.concat(ipsNoComments);

                        if ($scope.meta.sortDirection === "desc") {
                            return stuck_together.reverse();
                        }

                        return stuck_together;
                    };

                    $scope.filteredList = function() {
                        var filteredList = [];
                        var start, limit;

                        filteredList = $scope.trustedHosts;

                        // Sort
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            if ($scope.meta.sortBy === "hostIp") {
                                filteredList = filters.orderBy(filteredList, $scope.ipPadder, $scope.meta.sortReverse);
                            } else {
                                filteredList = $scope.orderByComments();
                            }
                        }

                        // Totals
                        $scope.meta.totalRows = $scope.trustedHosts.length;

                        // Pagination
                        start = ($scope.meta.pageNumber - 1) * $scope.meta.pageSize;
                        limit = $scope.meta.pageSize;
                        filteredList = filters.limitTo(filters.startFrom(filteredList, start), limit);

                        $scope.meta.pageNumberStart = start + 1;
                        $scope.meta.pageNumberEnd = ($scope.meta.pageNumber * $scope.meta.pageSize);


                        if ($scope.meta.totalRows === 0) {
                            $scope.meta.pageNumberStart = 0;
                        }

                        if ($scope.meta.pageNumberEnd > $scope.meta.totalRows) {
                            $scope.meta.pageNumberEnd = $scope.meta.totalRows;
                        }

                        $scope.meta.filteredList = filteredList;

                        return filteredList;
                    };

                    $scope.loadList = function(options) {
                        if (GreylistDataSource.enabled() && !$scope.list_loading) {
                            $scope.list_loading = true;
                            $scope.meta.filteredList = [];

                            var reset_focus = true;
                            var force = false;
                            if (typeof options !== "undefined") {
                                reset_focus = options.hasOwnProperty("reset_focus") ? options.reset_focus : true;
                                force = options.hasOwnProperty("force") ? options.force : false;
                            }

                            return GreylistDataSource.loadTrustedHosts(force)
                                .then(function() {
                                    $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                    $scope.filteredList();
                                    if (force) {
                                        return $scope.isServerNetblockTrusted();
                                    }
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally(function() {
                                    $scope.isListEmpty();
                                    if (reset_focus) {
                                        $scope.focusOnListEditor();
                                    }
                                    $scope.selecting_page_size = false;
                                    $scope.list_loading = false;
                                });
                        }
                        return null;
                    };

                    $scope.isServerNetblockTrusted = function() {
                        return GreylistDataSource.isServerNetblockTrusted()
                            .then(function(result) {
                                $scope.netblock = result.netblock;
                                $scope.netblockTrusted = result.status;

                                if ($scope.$parent) {
                                    $scope.$parent.growlTrustMyNeighbors(result.untrusted, result.status);
                                }
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.forceLoadTrustedHosts = function() {
                        $scope.trustedHosts = [];
                        $scope.meta.filteredList = [];
                        $scope.isListEmpty();
                        return $scope.loadList({ force: true });
                    };

                    $scope.isListEmpty = function() {

                    // if any of the lists are empty, show the empty list notice
                        var result = $scope.trustedHosts.length === 0 || $scope.meta.filteredList.length === 0;
                        if (result) {
                            $scope.selectAllCheckbox = false;
                        }

                        return result;
                    };

                    $scope.deleteConfirmationMessage = function() {
                        if ($scope.ips_to_delete.length === 1) {
                            return LOCALE.maketext("Do you want to permanently delete “[_1]” from the Trusted Hosts list?", $scope.ips_to_delete[0]);
                        } else {
                            return LOCALE.maketext("Do you want to permanently delete [quant,_1,record,records] from the Trusted Hosts list?", $scope.ips_to_delete.length);
                        }
                    };

                    $scope.deleteIps = function(is_single_deletion) {
                        $scope.clearModalInstance();
                        GreylistDataSource.deleteTrustedHosts($scope.ips_to_delete)
                            .then( function(results) {
                                $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                $scope.filteredList();
                                $scope.focusOnListEditor();
                                $scope.isListEmpty();

                                if (results.removed && results.removed.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully deleted “[_1]” from the Trusted Hosts list.", _.escape(results.removed[0])));
                                } else if (results.removed) {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the Trusted Hosts list.", results.removed.length));
                                }

                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the Trusted Hosts list.", results.not_removed.keys.length));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.ips_to_delete = [];
                                if (!is_single_deletion) {
                                    $scope.deselectAll();
                                }
                            });
                    };

                    $scope.confirmDeletion = function(trustedHostToDelete) {
                        if ($scope.trustedHosts.length === 0) {
                            return false;
                        }

                        $scope.delete_in_progress = true;
                        if (trustedHostToDelete !== void 0) {
                            $scope.ips_to_delete = [trustedHostToDelete.host_ip];
                            $scope.is_single_deletion = true;
                        } else {
                            var selected_items = [],
                                $selectedDomNodes = $(".selectItem:checked");

                            if ($selectedDomNodes.length === 0) {
                                return false;
                            }

                            $selectedDomNodes.each( function() {
                                selected_items.push($(this).data("ip"));
                            });
                            $scope.ips_to_delete = selected_items;
                            $scope.is_single_deletion = false;
                        }

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "modal/confirmTrustedHostDeletion.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.clearModalInstance = function() {
                        if ($scope.modal_instance) {
                            $scope.modal_instance.close();
                            $scope.modal_instance = null;
                        }
                    };

                    $scope.cancelDeletion = function() {
                        $scope.delete_in_progress = false;
                        $scope.ips_to_delete = [];
                        $scope.clearModalInstance();
                        $scope.focusOnListEditor();
                    };

                    $scope.confirmDeleteAll = function() {
                        if ($scope.trustedHosts.length === 0) {
                            return false;
                        }
                        $scope.delete_in_progress = true;

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "modal/confirmTrustedHostsDeleteAll.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.cancelDeleteAll = function() {
                        $scope.delete_in_progress = false;
                        $scope.clearModalInstance();
                        $scope.focusOnListEditor();
                    };

                    $scope.deleteAll = function() {
                        $scope.clearModalInstance();
                        GreylistDataSource.deleteAllTrustedHosts()
                            .then( function(results) {
                                $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                $scope.filteredList();
                                $scope.focusOnListEditor();
                                $scope.isListEmpty();
                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {

                                // we need to tell them how many we deleted and how many we did not delete
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the Trusted Hosts list.", results.removed.keys.length));
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the Trusted Hosts list.", results.not_removed.keys.length));
                                } else {
                                    growl.success(LOCALE.maketext("You have deleted all records from the Trusted Hosts list."));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.delete_in_progress = false;
                                $scope.deselectAll();
                            });
                    };

                    $scope.selectAll = function() {
                        if ($scope.trustedHosts.length === 0) {
                            return false;
                        }
                        $(".selectItem").prop("checked", true);
                        $scope.selectAllCheckbox = true;

                        return true;
                    };

                    $scope.deselectAll = function() {
                        if ($scope.trustedHosts.length === 0) {
                            return false;
                        }
                        $(".selectItem").prop("checked", false);
                        $scope.selectAllCheckbox = false;

                        return true;
                    };

                    $scope.focusOnListEditor = function() {
                        var batchField = $("#batchAdd");
                        var wait_id = setInterval( function() {
                            if (batchField.is(":visible")) {
                                batchField.focus();
                                batchField.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    $scope.trustMyServerNetblock = function() {
                        if ($scope.netblockTrusted) {
                            return;
                        }

                        var comment = "The server's neighboring IP addresses";

                        return $scope.$parent.addTrustedHost($scope.netblock,
                            comment)
                            .then(function(result) {
                                $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                $scope.filteredList();
                                if (result.status) {
                                    $scope.netblockTrusted = true;
                                    if (result.rejected.length > 0) {
                                        $scope.newTrustedHosts = result.rejected.join("\n");
                                    }
                                }
                            })
                            .finally(function() {
                                $scope.isListEmpty();
                            });
                    };

                    $scope.untrustMyServerNetblock = function() {
                        if (!$scope.netblockTrusted) {
                            return;
                        }
                        return GreylistDataSource.deleteTrustedHosts($scope.netblock)
                            .then(function(results) {
                                $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                $scope.filteredList();

                                if (results.removed) {
                                    $scope.netblockTrusted = false;
                                    if (results.removed.length === 1) {
                                        growl.success(LOCALE.maketext("You have successfully deleted “[_1]” from the Trusted Hosts list.", _.escape(results.removed[0])));
                                    } else {
                                        growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the Trusted Hosts list.", results.removed.length));
                                    }
                                }

                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the Trusted Hosts list.", results.not_removed.keys.length));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.isListEmpty();
                            });
                    };

                    $scope.addToTrustedHosts = function() {
                        if (!$scope.newTrustedHosts || $scope.addingBatchToTrustedHosts) {
                            return;
                        }

                        var batch = $scope.newTrustedHosts.split("\n");
                        var trimmed_batch = [];

                        for (var i = 0; i < batch.length; i++) {
                            var trimmed_item = batch[i].trim();
                            if (trimmed_item.length > 0 && trimmed_batch.indexOf(trimmed_item) === -1) {
                                trimmed_batch.push(trimmed_item);
                            }
                        }

                        $scope.addingBatchToTrustedHosts = true;

                        return $scope.$parent.addTrustedHost(trimmed_batch,
                            $scope.newTrustedHostComment)
                            .then(function(result) {
                                $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                $scope.filteredList();
                                if (result.status) {
                                    if (result.rejected.length > 0) {
                                        $scope.newTrustedHosts = result.rejected.join("\n");
                                    } else {
                                        $scope.newTrustedHosts = "";
                                        $scope.newTrustedHostComment = "";
                                    }
                                }
                            })
                            .finally(function() {
                                $scope.addingBatchToTrustedHosts = false;
                                $scope.focusOnListEditor();
                                $scope.isListEmpty();
                            });
                    };

                    $scope.updateTrustedHostComment = function() {
                        if ($scope.updating_comment) {
                            return;
                        }

                        $scope.updating_comment = true;
                        GreylistDataSource.addTrustedHosts([$scope.current_ip], $scope.current_comment)
                            .then( function(results) {
                                var rejected_messages = [];
                                $scope.trustedHosts = GreylistDataSource.trustedHosts;
                                $scope.filteredList();
                                for (var i = 0; i < results.updated.length; i++) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(results.updated[i])));
                                }

                                var ips_rejected = Object.keys(results.rejected);
                                for (var ed = 0; ed < ips_rejected.length; ed++) {
                                    rejected_messages.push(_.escape(ips_rejected[ed]) + ": " + _.escape(results.rejected[ips_rejected[ed]]));
                                }

                                if (rejected_messages.length > 0) {
                                    var accumulated_messages = LOCALE.maketext("Some records failed to update.") + "<br>";
                                    accumulated_messages += rejected_messages.join("<br>");
                                    growl.error(accumulated_messages);
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updating_comment = false;
                                $scope.cancelTrustedHostEditing();
                            });
                    };

                    $scope.ipPadder = function(trustedHost) {
                        return ipPad.ipPadder(trustedHost.host_ip);
                    };

                    $scope.$watch(function() {
                        return GreylistDataSource.enabled();
                    }, function() {
                        $scope.loadList({ force: true });
                    });

                    $scope.$watch(function() {
                        return $scope.$parent.isNetblockTrusted;
                    }, function() {
                        $scope.netblockTrusted = $scope.$parent.isNetblockTrusted;
                    });

                    // listen for the TrustedHosts.UPDATE_LIST event
                    var updateListEvent = $rootScope.$on("TrustedHosts.UPDATE_LIST", function() {
                        $scope.loadList();
                    });

                    // need to unbind this event when we destroy the scope
                    $scope.$on("$destroy", updateListEvent);

                    $scope.focusOnListEditor();
                }
            ]);

        return controller;
    }
);
