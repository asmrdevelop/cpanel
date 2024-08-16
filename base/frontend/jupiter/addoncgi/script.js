/* global $: false, PAGE: true */
/* exported toggleDisplay */

// collapse.tt
function toggleDisplay($dispEl, $linkEl, txtHide, txtShow, forceOpen) {
    if ($dispEl.is(":hidden") || forceOpen) {
        $dispEl.show();
        $linkEl.text(txtHide);
    } else {
        $dispEl.hide();
        $linkEl.text(txtShow);
    }
}

// install_section.tt
$(document).ready(function() {
    "use strict";
    $("#cpaddonsform_install").submit(function() {
        $("#spinner-install").show();
        $("#spinner-install-advanced").show();
        $("#btnSubmitInstall").attr("disabled", "disabled");
        $("#btnSubmitInstallAdvanced").attr("disabled", "disabled");
        $("#btnSubmitModeration").attr("disabled", "disabled");
    });
});

// install_section.tt - password setup
$(document).ready(function() {
    if (document.getElementById("password_strength") !== null) {
        var passwordValidator = CPANEL.password.setup("password", "password2", "password_strength", window.pwminstrength, "create_strong_password", "why_strong_passwords_link", "why_strong_passwords_text");
        CPANEL.validate.attach_to_form("submit", passwordValidator);
    }
});

// install_section.tt - validate the table prefix
$(document).ready(function() {
    var validCharacters = /[^a-zA-Z0-9]/;
    var validationContainer = $("#invalid-table-prefix-characters").closest(".validation-container");
    var submitButton = $("#btnSubmitInstall");
    var submitButtonAdvanced = $("#btnSubmitInstallAdvanced");

    function showHideWarning() {
        var inputVal = $(this).val();
        if ( validCharacters.test( inputVal ) ) {
            validationContainer.show();
            submitButton.prop("disabled", true);
            submitButtonAdvanced.prop("disabled", true);
        } else {
            validationContainer.hide();
            submitButton.prop("disabled", false);
            submitButtonAdvanced.prop("disabled", false);
        }
    }

    var input = $("#table_prefix");
    input.on("input", showHideWarning);
    showHideWarning.call( input );
});

// install_section.tt - show/hide the advanced configuration options
$(document).ready(function() {
    "use strict";
    function setupInstallSection() {

        var showTitle = LOCALE.maketext("Show Advanced Configuration");
        var hideTitle = LOCALE.maketext("Hide Advanced Configuration");
        var $btnAdvanced = $("#btnAdvanced");
        var $hidOneClick = $("input[name=oneclick]"); // Updates the oneclick variable on all the forms: install, uninstall, upgrade
        var $divAdvanced = $("#advanced");
        var $divOneClick = $("#oneclick");

        $("#cpaddonsform_uninstall").on("submit", function() {
            $("#btnUninstall").attr("disabled", "disabled");
            return true;
        });

        $("#cpaddonsform_upgrade").on("submit", function() {
            $("#btnUpgrade").attr("disabled", "disabled");
            return true;
        });

        // Return early if there is no related content.
        if ( !$divAdvanced.length || !$divOneClick.length ) {
            return;
        }

        /**
         * Adjust the form and focuses the correct element. Called
         * once the advance form is expanded and almost ready to use.
         *
         * @name finalizeAdvanced
         */
        function finalizeAdvanced() {
            $divOneClick
                .find("[name=subdomain]")
                .attr("disabled", "disabled");
            $divAdvanced
                .find("[name=subdomain]")
                .removeAttr("disabled");

            var $first = $("#cpaddonsform_install input[type=text]:first");
            var offset = $first.offset();
            $first.focus();
            $("html", "body").animate({
                scrollTop: offset.top,
                scrollLeft: offset.left,
            });
        }

        /**
         * Adjusts the form and focuses the first element. Called
         * once the oneclick form is expanded and almost ready to
         * use.
         *
         * @name  finalizeOneClick
         */
        function finalizeOneClick() {
            $divAdvanced
                .find("[name=subdomain]")
                .attr("disabled", "disabled");
            $divOneClick
                .find("[name=subdomain]")
                .removeAttr("disabled");

            $("#btnSubmitInstall").focus();
            $("#btnSubmitInstallAdvanced").focus();
        }

        var isOneClickReturn = PAGE && typeof (PAGE.oneclick) !== "undefined" ? PAGE.oneclick : true;

        // Prepare #oneclick for overlap
        $divOneClick.css({
            position: "absolute",
            width: "100%"
        });

        // Get the height of the two containers for later reference
        var oneClickHeight = $divOneClick.height();
        var advancedHeight = "100%";

        // Setup the initial conditions
        if (isOneClickReturn) {
            $hidOneClick.val(1);
            $btnAdvanced.text(showTitle);

            // Prepare #oneclick for overlap
            $divOneClick.css({
                opacity: 1,
                visibility: "visible"
            });

            // Prepare #advanced for overlap
            $divAdvanced.css({
                height: oneClickHeight,
                opacity: 0,
                visibility: "hidden"
            });
            finalizeOneClick();

        } else {
            $hidOneClick.val(0);
            $btnAdvanced.text(hideTitle);

            /* If we got to this state (advanced) because of the lack of contact email, don't allow
            * the user to switch to the one-click installer, which will fail. */
            if (!PAGE.has_contactemail) {
                $btnAdvanced.hide();
            }

            // Prepare #oneclick for overlap
            $divOneClick.css({
                height: "100%",
                opacity: 0,
                visibility: "hidden"
            });

            // Prepare #advanced for overlap
            $divAdvanced.css({
                height: advancedHeight,
                opacity: 1,
                visibility: "visible"
            });

            finalizeAdvanced();
        }

        /**
         * Called to show the one click form.
         *
         * @name showOneClick
         * @param  {Function} callback Additional steps to get the UI ready.
         */
        function showOneClick(callback) {
            var oneClickDropdown = $divOneClick.find("[name=subdomain]");
            var advancedDropdown = $divAdvanced.find("[name=subdomain]");
            var domain = advancedDropdown.val();
            var oneClickOptions = oneClickDropdown[0].options;

            for (var index = 0; index < oneClickOptions.length; index++) {
                if ( domain === oneClickOptions[index].value) {
                    oneClickDropdown.val(domain);
                    break;
                }
            }

            $divOneClick
                .css({
                    visibility: "visible",
                })
                .stop()
                .animate({
                    opacity: 1,
                }, {
                    queue: false,
                });

            $divAdvanced
                .stop()
                .animate({
                    height: oneClickHeight || $("#oneclick").height(),
                    opacity: 0,
                }, {
                    queue: false,
                    done: function() {
                        $divAdvanced.css({
                            visibility: "hidden",
                        });

                        if (callback && typeof callback === "function") {
                            callback();
                        }
                    },
                });
        }

        /**
         * Called to show the advanced configuration form.
         *
         * @name showAdvanced
         * @param  {Function} callback Additional steps to get the UI ready.
         */
        function showAdvanced(callback) {

            $divAdvanced
                .find("[name=subdomain]")
                .val(
                    $divOneClick
                        .find("[name=subdomain]")
                        .val()
                );

            $divOneClick
                .stop()
                .animate({
                    opacity: 0,
                }, {
                    queue: false,
                    done: function() {
                        $divOneClick.css({
                            visibility: "hidden",
                        });

                        if (callback && typeof callback === "function") {
                            callback();
                        }
                    },
                });

            $divAdvanced
                .css({
                    visibility: "visible",
                })
                .stop()
                .animate({
                    height: advancedHeight,
                    opacity: 1,
                }, {
                    queue: false,
                });
        }

        /**
         * Toggle the advanced configuration editor
         * visibility.
         *
         * @name toggleAdvancedConfiguration
         * @param  {Event} e
         */
        var toggleAdvancedConfiguration = function(e) {
            var showingOneClick = $hidOneClick.val() === "1" ? true : false; // jshint ignore:line
            if (showingOneClick) {
                $hidOneClick.val(0);
                $btnAdvanced.text(hideTitle);

                showAdvanced(finalizeAdvanced);

            } else {
                $hidOneClick.val(1);
                $btnAdvanced.text(showTitle);

                showOneClick(finalizeOneClick);
            }
        };

        $btnAdvanced.click(toggleAdvancedConfiguration);
    }

    // Workaround for Bootstrap using “display: none” instead of ”visibility: hidden” for tab-pane
    // This waits until the install tab is actually displayed before initializing it
    var $install = $("#install");

    if ( $install[0] ) {
        if ( !$install.hasClass("active") ) {

            var observer = new MutationObserver(function(mutations) {
                if ( $install.hasClass("active") ) {
                    setupInstallSection();
                    observer.disconnect();
                }
            });

            observer.observe($install[0], { attributes: true, attributeFilter: ["class"] });
        } else {
            setupInstallSection();
        }
    }

});

// install_section.tt - show hide license form
$(document).ready(function() {
    "use strict";

    // this functionality is only needed for Addons that require licenses
    if ( !PAGE.addon_needs_license ) {
        return;
    }

    var $installForm = $("#cpaddonsform_install");
    var $licenseForm = $("#cpaddons_form_license");
    var $licenseDropdown = $("#subdomain-license-dropdown");
    var $domainDropdown = $("#oneclick-subdomain");
    var $advancedDropdown = $("#advanced-subdomain");
    var $advanceButton = $("#btnAdvanced");
    var $checkbox = $("#licenseCheckbox");
    var $checkboxInfoBtn = $("#licenseCheckboxInfo");
    var $licenseInput = $("#licenseFormInput");
    var domainsWithLicense = PAGE.domains_with_license;

    var selectedDomain = null;

    /**
     * Show the License Form and disables the advanced configuration link.
     *
     * @name showLicenseForm
     * @param {String} domain Selected domain from the dropdown.
     */
    function showLicenseForm(domain) {
        $licenseForm.show();
        $installForm.hide();

        var productName = $("#productName").prop("title");
        $("#btnSubmitLicense").prop("href", "../store/purchase_product_init.html?product_name=" + productName + "&domain=" + domain);
    }

    /**
     * Show the Installation Form and enables the advanced configuration link.
     *
     * @name showInstallForm
     */
    function showInstallForm() {
        $licenseForm.hide();
        $installForm.show();

        if ($installForm.css("opacity") === "0") {
            $installForm.css({ opacity: 1 });
        }

        var oneClickHeight = $("#oneclick").height();
        var $divAdvanced = $("#advanced");
        $divAdvanced.css({ height: oneClickHeight });
    }


    /**
     * Disabled/Enable license check box
     *
     * @name disabledLicenseCheckbox
     * @param {Boolean} bool
     */
    function disabledLicenseCheckbox(bool) {
        $checkbox.prop("disabled", bool);
    }

    /**
     * If the domain is licensed or not, renders the proper form.
     *
     * @name renderForm
     * @param  {String} domain Selected domain from the dropdown.
     */
    function renderForm(domain) {
        var isChecked = $checkbox.prop("checked");
        selectedDomain = domain;

        // if domain has license do not allow insert license manually
        if ( domainsWithLicense[domain] ) {
            resetCheckboxState();
            disabledLicenseCheckbox(true);
            showInstallForm();
        } else if (isChecked) {
            showInstallForm();
            disabledLicenseCheckbox(false);
        } else {
            showLicenseForm(domain);
            disabledLicenseCheckbox(false);
        }
    }

    /**
     * Updates each dropdown from the 3 different forms.
     *
     * @name updateAllDropdowns
     * @param  {String} domain Selected domain from the dropdown.
     */
    function updateAllDropdowns(domain) {
        $advancedDropdown.val(domain);
        $domainDropdown.val(domain);
        $licenseDropdown.val(domain);
    }

    /**
     *  Updates all the dropdown values and shows the proper form.
     *
     * @name handleDropdown
     * @param  {Event} e
     */
    function handleDropdown(e) {
        var domain = e.target.selectedOptions[0].value;
        renderForm(domain);
        updateAllDropdowns(domain);
    }

    /**
     * Reset to a clean state all elements and values related to the license checkbox.
     *
     * @name resetCheckboxState
     */
    function resetCheckboxState() {
        $checkbox.prop("checked", false);
        $("#licenseFormInput input").val("");
        $("input[name=license_checkbox]").val("0");
        $licenseInput.hide();
    }

    /**
     * Event handler for the license checkbox.
     *
     * @name handleCheckbox
     */
    function handleCheckbox() {
        var isChecked = $checkbox.prop("checked");
        var isAdvancedShowing = $("#hidOneClick").val() === "0";

        if (isChecked) {
            $("input[name=license_checkbox]").val("1");
            if (!isAdvancedShowing) {
                showInstallForm();
            }
            $licenseInput.show();
        } else {
            $licenseInput.hide();
            $("input[name=license_checkbox]").val("0");

            if (isAdvancedShowing) {
                $advanceButton.click();
            }
            showLicenseForm(selectedDomain);
        }
    }

    /**
     * Event handler for the advance dropdown.
     *
     * @name handleAdvanceDropdown
     */
    function handleAdvanceDropdown(e) {
        var domain = e.target.selectedOptions[0].value;
        var isChecked = $checkbox.prop("checked");

        // don't allow to enter a license if the user already has one.
        if ( domainsWithLicense[domain] ) {
            resetCheckboxState();
            disabledLicenseCheckbox(true);
        }

        // don't allow to advanced install without any license.
        if (!isChecked && !domainsWithLicense[domain]) {
            disabledLicenseCheckbox(false);
            $checkbox.prop("checked", true);
            $licenseInput.show();
        }
        updateAllDropdowns(domain);

        // do not let switch to one click form if not available
        if (!PAGE.oneclick) {
            disabledLicenseCheckbox(true);
        }
    }

    function handleAdvanceButton() {
        var isLicenseShowing = $("#cpaddons_form_license").css("display") === "block";
        var isAdvancedShowing = $("#hidOneClick").val() === "0";

        if (isLicenseShowing) {
            showInstallForm();
            $checkbox.click();
        } else if (isAdvancedShowing && !$domainDropdown.val()) {

            // if current domain is not available on oneClickForm
            var firstValue = $domainDropdown[0].options[0].value;
            updateAllDropdowns(firstValue);
            renderForm(firstValue);
        }
    }

    function handleCheckboxInfoToggle() {
        $("#checkboxInfoText").toggle();
    }

    $domainDropdown.on("change", handleDropdown);
    $licenseDropdown.on("change", handleDropdown);
    $advancedDropdown.on("change", handleAdvanceDropdown);
    $checkbox.on("change", handleCheckbox);
    $advanceButton.on("click", handleAdvanceButton);
    $checkboxInfoBtn.on("click", handleCheckboxInfoToggle);

    // hide license input by default
    $licenseInput.hide();

    // on page load show/hide the correct form
    if ( PAGE.domains_without_root_install.length === 0 || !PAGE.oneclick ) {

        var isChecked = $checkbox.prop("checked");
        var currentDomain = $domainDropdown.val();
        if (!isChecked && !domainsWithLicense[currentDomain]) {
            $checkbox.click();
        }
        if (!PAGE.oneclick) {
            disabledLicenseCheckbox(true);
        }
        showInstallForm();
    } else {
        renderForm($domainDropdown.val());
    }
});

// action_upgrade.tt
$(document).ready(function() {
    "use strict";
    $("#txtForce").bind("input propertychange", function() {
        var val = $("#txtForce").val();
        if (!val || val !== window.force_text) { // passed in template
            $("#btnForce").attr("disabled", "disabled");
        } else {
            $("#btnForce").removeAttr("disabled");
        }
    });

    $("#cpaddonsupform").submit(function() {
        $("#spinner-install").show();
        $("#btnForce").attr("disabled", "disabled");
    });
});

// verify_uninstall.tt
$(document).ready(function() {
    var clicked = false;
    $("#btnConfirmUninstall").click(function() {
        if (!clicked) {
            clicked = true;
            $(this).attr("disabled", "disabled");
            $("#spinner-uninstall").show();
            return true;
        }
        return false;
    });
});

// verify_upgrade.tt
$(document).ready(function() {
    var clicked = false;
    $("#btnConfirmUpgrade").click(function() {
        if (!clicked) {
            clicked = true;
            $(this).attr("disabled", "disabled");
            $("#spinner-upgrade").show();
            return true;
        }
        return false;
    });
});

// moderation_request_form.tt
$(document).ready(function() {
    $("#btnSubmitModerationRequest").click(function() {
        $("#spinner-submit").show();
    });

    // Focus and move the cursor to the end of the text.
    var text = $("#txtModerationRequest").val();
    $("#txtModerationRequest").focus().val("").val(text);
});
