/*
# templates/autossl/views/view_logs_controller.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100, -W089 */
/* eslint-disable camelcase */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/formWaiting",
    ],
    function(_, angular, LOCALE, CJT, CJT_PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "view_logs_controller", [
                "$scope",
                "$timeout",
                "manageService",
                "growl",
                "PAGE",
                function($scope, $timeout, manageService, growl, PAGE) {
                    function growlError(result) {
                        return growl.error( _.escape(result.error) );
                    }

                    manageService.groom_logs_catalog(PAGE.logs_catalog);

                    var providerDisplayName = {};
                    PAGE.provider_info.forEach( function(p) {
                        providerDisplayName[p.module_name] = p.display_name;
                    } );

                    // do this while CJT2’s CLDR is broken.
                    var cjt1_LOCALE = window.LOCALE;

                    var log_level_fontawesome = {

                        // warn: "fa-exclamation-triangle",
                        warn: "exclamation-triangle",
                        error: "minus-square",
                        out: "info-circle",
                        success: "check",
                    };

                    var log_level_localized = {
                        success: LOCALE.maketext("SUCCESS"),
                        warn: LOCALE.maketext("WARN"),
                        error: LOCALE.maketext("ERROR"),
                    };

                    var unparsable_template = LOCALE.maketext("Unparsable log data ([_1]):", "__ERR__");

                    angular.extend( $scope, {
                        log_level_localized: log_level_localized,

                        log_level_fontawesome: log_level_fontawesome,

                        logs_catalog: manageService.get_logs_catalog(),
                        chosen_log: manageService.get_logs_catalog()[0],

                        datetime: cjt1_LOCALE.local_datetime.bind(cjt1_LOCALE),

                        get_provider_display_name: manageService.get_provider_display_name,

                        fetch_logs_catalog: function() {
                            return manageService.refresh_logs_catalog().then(
                                function(catalog) {
                                    $scope.logs_catalog = catalog;
                                    var old_chosen_log = $scope.chosen_log;
                                    $scope.chosen_log = null;

                                    if (old_chosen_log) {
                                        for (var c = 0; c < catalog.length; c++) {
                                            if (old_chosen_log.provider !== catalog[c].provider) {
                                                continue;
                                            }
                                            if (old_chosen_log.start_time !== catalog[c].start_time) {
                                                continue;
                                            }

                                            $scope.chosen_log = catalog[c];
                                            break;
                                        }
                                    }

                                    if (!$scope.chosen_log) {
                                        $scope.chosen_log = catalog[0];
                                    }

                                    return;
                                },
                                growlError
                            );
                        },

                        // This optimization is ugly, but AngularJS was too slow
                        // when rendering thousands of DOM nodes.
                        _log_data_to_html: function(logs) {
                            var rows = [];

                            var log_level_html = {};
                            for (var key in log_level_localized) {
                                log_level_html[key] = _.escape(log_level_localized[key]);
                            }

                            var indentTimestamp;

                            for (var l = 0; l < logs.length; l++) {
                                var entry = logs[l];
                                var div_class = "logentry-" + entry.type;
                                if (("" + entry.indent) !== "0") {
                                    div_class += " indent" + entry.indent;
                                }
                                var r_html = "<div class='" + div_class + "'>";
                                if (log_level_fontawesome[entry.type]) {
                                    r_html += " <span class='fas fa-" + log_level_fontawesome[entry.type] + "'></span>";
                                }

                                var curIndentTimestamp = [entry.indent, entry.timestamp_epoch].join();

                                if ((curIndentTimestamp !== indentTimestamp) && entry.timestamp_epoch) {
                                    indentTimestamp = curIndentTimestamp;
                                    r_html += " <span>" + LOCALE.local_datetime(entry.timestamp_epoch, "time_format_medium") + "</span>";
                                }


                                if (log_level_localized[entry.type]) {
                                    r_html += " <span>" + log_level_html[entry.type] + "</span>";
                                }

                                if ("contents" in entry) {
                                    r_html += " " + _.escape(entry.contents);
                                } else {
                                    r_html += " <span class='log-unparsed'>??? " + unparsable_template.replace(/__ERR__/, _.escape(entry.parse_error)) + " " + _.escape(entry.raw) + "</span>";
                                }

                                r_html += "</div>";

                                rows.push(r_html);
                            }

                            return rows.join("");
                        },

                        log_submit: function() {
                            var loadData = Object.create($scope.chosen_log);

                            $scope.log_load_in_progress = true;

                            return manageService.get_log(loadData).then(
                                function(resp) {
                                    $scope.current_loaded_log = resp;
                                    $timeout(
                                        function() {
                                            document.getElementById("current_loaded_log_html").innerHTML = $scope._log_data_to_html(resp);
                                        }
                                    );

                                    loadData.start_time_epoch = $scope.chosen_log.start_time_epoch;
                                    $scope.last_load_data = loadData;
                                },
                                growlError
                            ).then( function() {
                                $scope.log_load_in_progress = false;
                            } );
                        },
                    } );

                    manageService.restore_and_save_scope(
                        "view_logs",
                        $scope,
                        [
                            "chosen_log",
                            "last_load_data",
                            "current_loaded_log",
                        ]
                    );
                }
            ]
        );

        return controller;
    }
);
