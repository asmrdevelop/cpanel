/*
# indexmanager/index.js                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, SetNvData: false, cpanel_jsonapi2: false */

define(
    [
        "jquery",
        "bootstrap"
    ], function($) {
        "use strict";

        var $ddlDomain  = $("#ddlDomainSelect");

        $("#modalSettings").on("shown.bs.modal", function() {

            // yield so the modal can finish drawing so the focus
            // will actually take.
            setTimeout(function() {
                var $checked = $("input[name=dirselect]:checked");
                if ($checked.length) {
                    $checked.focus();
                } else {
                    $("#dirselect_home").focus();
                }
            }, 5);
        });

        $("#btnSettingsSave").click(function(e) {
            e.preventDefault();
            var option = $("input[name=dirselect]:checked").val();
            var domain = $ddlDomain.val();
            var alwaysOpenDir = $("#settings_saved").is(":checked");

            if (alwaysOpenDir) {
                SetNvData(
                    "optionselect_index",
                    option + ":" + domain + ":" + (alwaysOpenDir ? "1" : "0"),
                    nvdataCallback
                );
            } else {
                if (option === "home") {
                    reloadPage(PAGE.homeFolder);
                } else if (option === "webroot") {
                    reloadPage(PAGE.pubHtmlFolder);
                } else {
                    cpanel_jsonapi2(docrootcallback, "DomainLookup", "getdocroot", "domain", domain);
                }
            }
        });

        function nvdataCallback(result) {
            if (result) {
                window.location.href = window.location.href.split("?")[0];
            }
        }

        function docrootcallback(result) {
            if (result) {
                reloadPage(result[0].docroot);
            }
        }

        function reloadPage(path) {
            var path = encodeURIComponent(path);
            window.location.href = updateQueryStringParameter(window.location.href, "dir", path);
        }

        function updateQueryStringParameter(uri, key, value) {
            var re = new RegExp("([?&])" + key + "=.*?(&|$)", "i");
            var separator = uri.indexOf("?") !== -1 ? "&" : "?";

            if (uri.match(re)) {
                return uri.replace(re, "$1" + key + "=" + value + "$2");
            } else {
                return uri + separator + key + "=" + value;
            }
        }

        var $selWebRoot = $("#dirselect_webroot");
        $selWebRoot.change(function() {
            if ($selWebRoot.is(":checked")) {
                $ddlDomain.prop( "disabled", true );
            } else {
                $ddlDomain.prop( "disabled", false );
            }
        });

        var $selHome = $("#dirselect_home");
        $selHome.change(function() {
            if ($selHome.is(":checked")) {
                $ddlDomain.prop( "disabled", true );
            } else {
                $ddlDomain.prop( "disabled", false );
            }
        });

        var $selDomainRoot = $("#optionselect_domainrootselect_radio");
        $selDomainRoot.change(function() {
            if ($selDomainRoot.is(":checked")) {
                $ddlDomain.prop( "disabled", false );
            } else {
                $ddlDomain.prop( "disabled", true );
            }
        });

        var $exampleIndexFiles = $("#example-index-files");
        $("#toggle-example-index-files").click(function() {
            if ($exampleIndexFiles.hasClass("hidden")) {
                $exampleIndexFiles.removeClass("hidden");
                this.innerText = PAGE.hideLabel;
            } else {
                $exampleIndexFiles.addClass("hidden");
                this.innerText = PAGE.showLabel;
            }
        });
    }
);