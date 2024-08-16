/* exported handle_reseller_redirect_action */
function handle_reseller_redirect_action(action) {
    var formEl = document.getElementById("reseller_actions_" + action);
    var inputEl = document.getElementById("reseller_actions_" + action + "_user");
    var userEl = document.getElementById("reseller_actions_select");
    var user = userEl.options[userEl.selectedIndex].value;
    if (inputEl) {
        inputEl.value = user;
    }
    if (formEl.action.match("%user%")) {
        formEl.action = formEl.action.replace("%user%", user);
    }
    formEl.submit();
    return false;
}

/* exported handle_reseller_select_update */
function handle_reseller_select_update(sel) {
    var links = document.querySelectorAll(".reseller_actions div.reseller_action a");
    var links_ct = links.length;

    var username = sel.options[ sel.selectedIndex ].value;

    for (var l = 0; l < links_ct; l++) {
        links[l].href = links[l].href.replace(/=.*/, "=" + encodeURIComponent(username));
    }
}
