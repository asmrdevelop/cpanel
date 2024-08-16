/*
# cpanel - base/webmail/jupiter/_assets/base.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global SetNvData: false, NVData: false,
    $: false */
/* jshint -W064 */

(function() {
    "use strict";

    /**
     * Sets the default_webmail_app in NVData
     * @param  {String} client
     */
    function setDefault(client) {
        if (client && client.length > 0) {
            if (window.NVData["default_webmail_app"] !== client) {
                SetNvData("default_webmail_app", client, handleSetNvData);
            } else {
                selectDefault(client);
            }
        }
    }

    /**
     * Update the default mail client on both user dropdown and on index page.
     * @param  {object} evt
     */
    function updateDefaultHandler(client) {
        if (typeof selectDefault !== "undefined" && $.isFunction(selectDefault)) {
            selectDefault(client);
        }

        if (typeof updateDefaultSelection !== "undefined" && $.isFunction(updateDefaultSelection)) {
            updateDefaultSelection();
        }
    }

    /**
     * Select default mail client in the user dropdown
     * @param  {String} client default webmail client
     */
    function selectDefault(client) {
        $("span[data-default-webmail-app]").each(function() {
            var mailClient = $(this);
            if (mailClient.attr("data-default-webmail-app") === client) {
                mailClient.removeClass("far fa-spinner fa-spin").addClass("fas fa-star");
            } else {
                mailClient.removeClass("fas fa-spinner fa-spin").addClass("far fa-star");
            }
        });
    }

    /**
    * Set the loading indicator in the user dropdown
    */
    function setLoadingIndicator(client) {
        var mailClientImg = $("span[data-default-webmail-app=" + client + "]");
        mailClientImg.removeClass("far fa-star").addClass("fas fa-spinner fa-spin");
    }


    /**
     * Callback after setting the NVData
     * @param  {Object} data data returned from SetNvData method
     */
    function handleSetNvData(data) {
        if (data) {
            window.NVData["default_webmail_app"] = NVData["default_webmail_app"];

            updateDefaultHandler(NVData["default_webmail_app"]);
        }
    }

    /*
    * Updates the default selection on the mailclient template
    */
    function updateDefaultSelection() {

        /* this is probably obsolete, but needs to be confirmed */
        $("#mailClientList .panel").each(function() {
            if ($(this).attr("data-default-webmail-app") === NVData["default_webmail_app"]) {
                $(this).removeClass("panel-default").addClass("panel-primary");
                $(this).children("a.mail-client-action-link").removeClass("show").addClass("hide");
                $(this).find(".default-mail-client").removeClass("hide").addClass("show");
            } else {
                $(this).removeClass("panel-primary").addClass("panel-default");
                $(this).children("a.mail-client-action-link").removeClass("hide").addClass("show");
                $(this).find(".default-mail-client").removeClass("show").addClass("hide");
            }
        });
    }

    function launchActiveClient() {
        window.location = window.NVData["mail_clients"][window.NVData["active_webmail_app"]]["url"];
    }

    function selectActive(clientToActivate) {
        var mailClients = window.NVData["mail_clients"];

        if (!clientToActivate || !mailClients || !mailClients.hasOwnProperty(clientToActivate)) {
            clientToActivate = getActiveWebmailApp();
        }

        var selectedOption = document.getElementById("setAsActive-" + window.NVData["active_webmail_app"]);
        if (selectedOption) {
            selectedOption.classList.add("disabled");
            selectedOption.setAttribute("aria-disabled", "true");
            selectedOption.setAttribute("tabindex", "-1");
        }

        if (window.NVData["active_webmail_app"] !== clientToActivate) {
            window.NVData["active_webmail_app"] = clientToActivate;

            var newOption = document.getElementById("setAsActive-" + clientToActivate);
            if (newOption) {
                newOption.classList.add("disabled");
                newOption.setAttribute("tabindex", "-1");
                newOption.setAttribute("aria-disabled", "true");
                if (selectedOption) {
                    selectedOption.classList.remove("disabled");
                    selectedOption.setAttribute("aria-disabled", "false");
                    selectedOption.setAttribute("tabindex", "0");
                }
            }
        }

        var logoContainer = document.getElementById("activeClientLogoContainer");

        if (logoContainer) {
            var oldLogo = document.getElementById("activeClientLogo");
            var newLogo = document.createElement("img");
            newLogo.src = mailClients[clientToActivate].icon;
            newLogo.id = "activeClientLogo";
            newLogo.alt = LOCALE.maketext("Your currently active mail client is “[_1]”.", clientToActivate);
            newLogo.setAttribute("aria-hidden", "true");
            if (oldLogo) {
                logoContainer.replaceChild(newLogo, oldLogo);
            } else {
                logoContainer.appendChild(newLogo);
            }

            var setAsDefaultCheckbox = document.getElementById("setActiveAsDefault");
            setAsDefaultCheckbox.checked = clientToActivate === window.NVData["default_webmail_app"];
        }
    }

    function getActiveWebmailApp() {

        // get the defined default app if available
        var defaultClient = window.NVData["default_webmail_app"];

        // if the default isn't installed, figure out a fallback

        var roundcubeIsInstalled = window.NVData["mail_clients"].hasOwnProperty("roundcube");
        var defaultIsInstalled = defaultClient && window.NVData["mail_clients"].hasOwnProperty(defaultClient);

        if (defaultIsInstalled) {

            // good to go
            return defaultClient;
        } else if (roundcubeIsInstalled) {

            // if default client is undefined or not installed
            // and roundcube is installed, return that
            return "roundcube";
        } else {

            // roundcube or whatever the default is isn't installed
            // pick the first app out of the available clients pool
            var availableApps = Object.keys(window.NVData["mail_clients"]);
            return availableApps[0];
        }
    }

    $(function() {
        var activeClient = getActiveWebmailApp();
        var defaultClient = window.NVData["default_webmail_app"];
        window.NVData["active_webmail_app"] = activeClient;

        if (defaultClient) {
            selectDefault(defaultClient);
        }
        selectActive(activeClient);

        // user preferences dropdown
        $("a.app-fav").click(function(event) {
            var client = $(this).attr("data-default-webmail-app");
            setLoadingIndicator(client);
            setDefault(client);
            event.stopPropagation();
        });

        // mail client button in index page
        $("a.mail-client-action-link").click(function() {
            var client = $(this).attr("data-default-webmail-app");
            SetNvData("default_webmail_app", client, handleSetNvData);
        });

        var setDefaultCheckbox = document.getElementById("setActiveAsDefault");
        var launchActiveButton = document.getElementById("launchActiveButton");
        var logoButton = document.getElementById("activeClientLogoContainer");

        var mailClients = window.NVData["mail_clients"];


        if (mailClients) {
            Object.keys(window.NVData["mail_clients"]).forEach(function(clientId) {
                function selectNewClient(event) {
                    if (event.target.matches("img.availableClientDock") &&
                        event.target.parentElement.classList.contains("disabled") ) {
                        return;
                    }
                    selectActive(clientId);
                }
                var activateButton = document.getElementById("setAsActive-" + clientId);
                if (activateButton) {
                    activateButton.addEventListener("click", selectNewClient, false);
                }
            });

            if (setDefaultCheckbox) {
                if (activeClient === window.NVData["default_webmail_app"] && mailClients.hasOwnProperty(window.NVData["active_webmail_app"])) {
                    setDefaultCheckbox.checked = true;
                }
            }
        }

        if (setDefaultCheckbox) {
            setDefaultCheckbox.addEventListener("click", function(event) {
                SetNvData("default_webmail_app", setDefaultCheckbox.checked ? window.NVData["active_webmail_app"] : "", handleSetNvData);
            });
        }

        if (launchActiveButton) {
            launchActiveButton.addEventListener("click", launchActiveClient);
        }

        if (logoButton) {
            logoButton.addEventListener("click", launchActiveClient);
            logoButton.focus();
        }

    });

})();
