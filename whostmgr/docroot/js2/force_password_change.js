var all_checkboxes = CPANEL.Y.all("#force_password_change_tbody input[type=checkbox]");
var checkboxes_count = all_checkboxes.length;

function select_all(unselect) {
    for (var c = 0; c < all_checkboxes.length; c++) {
        all_checkboxes[c].checked = !unselect;
        all_checkboxes[c].onclick();
    }
}

function unselect_all() {
    return select_all(true);
}

function sync_changed(el) {
    var func = (el.checked === el.defaultChecked) ? "removeClass" : "addClass";
    DOM[func](DOM.getAncestorByTagName(el, "tr"), "changed");
}

function sync_users(users) {
    for (var u = 0, cur_u; cur_u = users[u]; u++) {
        var input = FORM["force_password_change-" + cur_u];
        input.defaultChecked = input.checked;
        sync_changed(input);
    }
}

var FORM = DOM.get("force_password_change_form");

function ajax_save() {
    var form_data = CPANEL.dom.get_data_from_form(FORM, {
        include_unchecked_checkboxes: 0
    });
    var users = {};
    for (var key in form_data) {
        var match = key.match(/^force_password_change-(.*)$/);
        if (match) {
            users[match[1]] = Number(form_data[key]);
        }
    }

    // This API call can (pretty easily) return a partial success; i.e.,
    // if one account succeeds, then the next fails, the API call just stops
    // without rolling back the account that succeeded.
    var callback = {
        success: function(o) {
            if (o.cpanel_data) {
                sync_users(o.cpanel_data);
            }
        },
        failure: function(o) {
            if (o.cpanel_data && o.cpanel_data.updated) {
                sync_users(o.cpanel_data.updated);
            }
        }
    };

    var api = CPANEL.api({
        progress_panel: {
            status_html: LOCALE.maketext("Saving …"),
            source_el: "save_button"
        },
        func: "forcepasswordchange",
        data: {
            users_json: YAHOO.lang.JSON.stringify(users)
        },
        callback: callback
    });
}
