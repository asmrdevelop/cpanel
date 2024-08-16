/*
# cpanel - base/frontend/jupiter/htaccess/leechprotect/dohtaccess.js
                                                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    window.addEventListener("load", function() {

        var emailTextBox = document.leechform.email;
        var emailCheckBox = document.leechform.emailcheck;
        emailTextBox.addEventListener("change", function checkemail() {
            if (emailTextBox.value === "") {
                emailCheckBox.checked = false;
            } else {
                emailCheckBox.checked = true;
            }
        });

        emailCheckBox.addEventListener("change", function killemail() {
            if (emailCheckBox.checked === false) {
                emailTextBox.backupValue = emailTextBox.value;
                emailTextBox.value = "";
            } else {
                emailTextBox.value = emailTextBox.backupValue || (PAGE.email !== "Invalid" ? PAGE.email : "");
            }
        });
    });
})();
