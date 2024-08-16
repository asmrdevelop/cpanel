if (!window.LOCALE) {
    window.LOCALE = new CPANEL.Locale();
}

function get_hook_by_id(id) {
    for (var key in hooks_by_key) {
        for (var a = hooks_by_key[key].length - 1; a >= 0; a--) {
            var action = hooks_by_key[key][a];
            if (action.id === id) {
                return action;
            }
        }
    }

    throw "No hook: " + id;
}

// Do this in JS because we want to ignore display:none rows
var stripe_classes = {
    "true": "shown-odd",
    "false": "shown-even"
};

function stripe_tbody(tbody) {
    var shown_idx = 0;
    var row_length = tbody.rows.length;

    [].forEach.call(tbody.rows, function(r) {
        if (DOM.getStyle(r, "display") !== "none") {
            var old_class = stripe_classes[!(shown_idx % 2)];
            var new_class = stripe_classes[ !!(shown_idx % 2)];
            DOM.replaceClass(r, old_class, new_class);
            shown_idx++;
        }
    });
}
EVENT.onDOMReady(function() {
    CPANEL.Y.all("table.hooks-table tbody").forEach(stripe_tbody);
});

function toggle_enabled(id, clicked) {
    var hook = get_hook_by_id(id);
    var to_enable = !parseInt(hook.enabled);

    var table = DOM.getAncestorByTagName(clicked, "table");
    var overlay = new CPANEL.ajax.Page_Progress_Overlay(null, {
        covers: table,
        status_html: to_enable ? LOCALE.maketext("Enabling hook …") : LOCALE.maketext("Disabling hook …")
    });
    overlay.show();

    var success = function suc() {
        hook.enabled = to_enable ? 1 : 0;
        var row = DOM.getAncestorByTagName(clicked, "tr");
        if (to_enable) {
            var attr = CPANEL.Y(row).one("span.enabled-off");
            attr.title = LOCALE.maketext("This hook is enabled.");
            CPANEL.util.set_text_content(clicked, LOCALE.maketext("Disable"));
            DOM.replaceClass(attr, "enabled-off", "enabled-on");
            DOM.replaceClass(row, "hook-disabled", "hook-enabled");
        } else {
            var attr = CPANEL.Y(row).one("span.enabled-on");
            attr.title = LOCALE.maketext("This hook is disabled.");
            CPANEL.util.set_text_content(clicked, LOCALE.maketext("Enable"));
            DOM.replaceClass(attr, "enabled-on", "enabled-off");
            DOM.replaceClass(row, "hook-enabled", "hook-disabled");

        }
    };

    CPANEL.api({
        func: "edit_hook",
        data: {
            id: id,
            enabled: to_enable ? 1 : 0
        },
        catch_api_errors: true,
        callback: CPANEL.ajax.build_page_callback(success, {
            hide_on_return: overlay
        })
    });
}

var sorted_desc = {};

function reverse_sort(category, clicked) {
    var desc = sorted_desc[category] = !sorted_desc[category];

    apply_sort(category, desc);

    if (desc) {
        DOM.replaceClass(clicked, "sorted-asc", "sorted-desc");
    } else {
        DOM.replaceClass(clicked, "sorted-desc", "sorted-asc");
    }
};

// TODO: This function originally sorted every table on the page,
// so it has some loop stuff that doesn't need to be around anymore.
// It can be removed at some later point.

function apply_sort(category, reverse) {
    var row_cat_stg_cache = {};

    var tbodies = CPANEL.Y.all("#" + category + "-table tbody");
    var cur_category;
    var row_sort_event = function(r) {
        if (DOM.hasClass(r, "event-stage")) {
            return row_cat_stg_cache[r.id] = cur_category + "-" + CPANEL.util.get_text_content(CPANEL.Y(r).one(".event")).replace(/:/g, "-");
        } else {
            var id = r.id.replace(/^hook-/, "");
            var js_hook = get_hook_by_id(id);
            return row_cat_stg_cache[r.id] = js_hook.category + "-" + js_hook.event.replace(/:/g, "-");
        }
    };
    row_sort_event.reverse = reverse;

    var row_sort_stage = function(r) {
        var stage;
        if (DOM.hasClass(r, "event-stage")) {
            stage = CPANEL.util.get_text_content(CPANEL.Y(r).one(".stage"));
        } else {
            var id = r.id.replace(/^hook-/, "");
            var js_hook = get_hook_by_id(id);
            stage = js_hook.stage;
        }

        var cat_stg = row_cat_stg_cache[r.id];
        return stage_orders[cat_stg].indexOf(stage);
    };

    // This function is never reversed.
    var row_sort_is_parent = function(r) {
        return DOM.hasClass(r, "event-stage") ? 0 : 1;
    };

    tbodies.forEach(function(tb) {
        cur_category = tb.parentNode.id.replace(/-table$/, "");
        var rows = CPANEL.Y(tb).all("tr");
        rows.sort_by(row_sort_event, row_sort_stage, row_sort_is_parent);
        rows.forEach(function(r) {
            tb.appendChild(r);
        });

        stripe_tbody(tb);
    });
}

// Args can be either an ID or (category, event, stage)

function _make_key(category, event, stage) {
    if (!event && !stage) {
        var hook = get_hook_by_id(arguments[0]);
        category = hook.category;
        event = hook.event;
        stage = hook.stage;
    }

    return [category, event, stage].join("-").replace(/:/g, "-");
}

function get_hook_and_siblings_by_id(id) {
    var hook = get_hook_by_id(id);
    return hooks_by_key[_make_key(hook.category, hook.event, hook.stage)];
}

String.prototype.html_smart_break = function() {
    return this.replace(/(::|\-)/g, "$1&shy;");
};

var shown = {};
var overlay_manager = new YAHOO.widget.OverlayManager();

function show_details(id, src) {
    var hook_data = get_hook_by_id(id);

    if (shown[id]) {
        return;
    }

    hook_data = YAHOO.lang.augmentObject({}, hook_data);
    hook_data.hook = hook_data.hook.html_encode();
    hook_data.notes = hook_data.notes || "";
    hook_data.stage_description = stage_descriptions[_make_key(hook_data.id)];

    for (var attr in {
        rollback: 0,
        check: 0
    }) {
        if (hook_data[attr]) {
            hook_data[attr] = hook_data[attr].html_encode();
        }
    }

    for (var attr in hook_data) {
        if (typeof hook_data[attr] === "string") {
            hook_data[attr] = String(hook_data[attr]).html_smart_break();
        }
    }

    var dialog = shown[id] = new CPANEL.ajax.Common_Action_Dialog(null, {
        close: true,
        modal: false,
        clicked_element: src,
        errors_in_notice_box: true,
        show_status: true,
        status_template: LOCALE.maketext("Saving …"),
        header_html: LOCALE.maketext("View/Edit Hook Details"),
        form_template: "details_template",
        form_template_variables: hook_data,
        zIndex: 1,
        api_calls: [{
            api_function: "edit_hook",
            data: function() {
                return {
                    id: id,
                    notes: this.form.hook_notes.value.trim()
                };
            },
            success_function: function() {
                var notes = this.form.hook_notes.value.trim();
                var cell = CPANEL.Y("hook-" + id).one("td.notes");
                CPANEL.util.set_text_content(cell, notes);
                get_hook_by_id(id).notes = notes;
            }
        }]
    });

    var buttons = dialog.cfg.getProperty("buttons");
    buttons[0].text = LOCALE.maketext("Save");
    buttons[1].text = LOCALE.maketext("Close");

    // Render before showing so that all the classes are correctly applied
    // before we animate open.
    dialog.render();

    overlay_manager.register(dialog);
    EVENT.on(dialog.element, "click", dialog.focus, dialog, true);

    DOM.addClass(dialog.element, "details-panel");
    DOM.addClass(dialog.element, hook_data.enabled ? "enabled-on" : "enabled-off");
    DOM.addClass(dialog.element, hook_data.blocking ? "blocking-on" : "blocking-off");
    DOM.addClass(dialog.element, hook_data.escalateprivs ? "escalate-on" : "escalate-off");
    DOM.addClass(dialog.element, hook_data.check ? "check-on" : "check-off");
    DOM.addClass(dialog.element, hook_data.rollback ? "rollback-on" : "rollback-off");

    dialog.after_hideEvent.subscribe(function() {
        if (dialog.cfg) {
            dialog.destroy();
        }
    });

    dialog.destroyEvent.subscribe(function(e) {
        delete shown[id];
    });

    dialog.animated_show();
}

function delete_prompt(id, src) {
    var hook_data = get_hook_by_id(id);

    var dialog = new CPANEL.ajax.Common_Action_Dialog(null, {
        close: true,
        clicked_element: src,
        show_status: true,
        status_template: LOCALE.maketext("Deleting hook …"),
        header_html: LOCALE.maketext("Delete a Hook"),
        form_template: "delete_prompt_template",
        form_template_variables: {
            hook: hook_data.hook.html_encode(),
            insertion: [hook_data.category, hook_data.event, hook_data.stage].join("::").html_encode()
        },
        api_calls: [{
            api_function: "delete_hook",
            data: {
                id: id
            },
            success_function: function() {
                var hooks = get_hook_and_siblings_by_id(id);
                var index = hooks.indexOf(hook_data);
                hooks.splice(index, 1);

                var row = DOM.get("hook-" + id);
                var tbody = row.parentNode;
                tbody.removeChild(row);
                stripe_tbody(tbody);

                var children = tbody.childNodes;
                var has_children = false;

                for (var i = 0; i < children.length; i++) {
                    if (children[i].nodeType === 1) {
                        has_children = true;
                        break;
                    }
                }

                if (!has_children) {
                    var container = DOM.get(hook_data.category + "-container");
                    container.parentNode.removeChild(container);

                    if (!CPANEL.Y.all(".category-container").length) {
                        var hooks_area = CPANEL.Y.one("#hooks_section");
                        hooks_area.parentNode.removeChild(hooks_area);
                        no_hooks_notice.animated_show();
                        CPANEL.animate.fade_out(CPANEL.Y.one(".legend-box"));
                    }
                }
            }
        }]
    });

    dialog.render();
    DOM.addClass(dialog.element, "delete-prompt");

    dialog.animated_show();
}

var RIGHT_ARROW = String.fromCharCode(9654);
var DOWN_ARROW = String.fromCharCode(9660);

function toggle_hooks(key, clicked) {
    var rows = CPANEL.Y.all("tr.hook." + key + "-hook");

    if (rows.length) {
        if (DOM.getStyle(rows[0], "display") === "none") {
            rows.forEach(function(r) {
                DOM.setStyle(r, "display", "");
            });
            CPANEL.util.set_text_content(clicked, DOWN_ARROW);
        } else {
            rows.forEach(function(r) {
                DOM.setStyle(r, "display", "none");
            });
            CPANEL.util.set_text_content(clicked, RIGHT_ARROW);
        }
    }

    stripe_tbody(DOM.getAncestorByTagName(clicked, "tbody"));
}

function expand_all() {

    // No need to hide anything since update_table_search() will do that.
    CPANEL.Y.all(".toggle-link").forEach(function(lk) {
        CPANEL.util.set_text_content(lk, DOWN_ARROW);
    });

    update_table_search();
}

function collapse_all() {
    CPANEL.Y.all("tr.hook").forEach(function(r) {
        DOM.setStyle(r, "display", "none");
    });
    CPANEL.Y.all(".toggle-link").forEach(function(lk) {
        CPANEL.util.set_text_content(lk, RIGHT_ARROW);
    });
}

function update_table_search() {
    var search_box = DOM.get("table_search_box");
    if (!search_box) {
        return;
    }

    var needle = new RegExp(search_box.value.trim().regexp_encode(), "i");
    var rows = CPANEL.Y.all("#hooks_section tbody tr");

    var containers_shown = CPANEL.Y.all(".category-container").length;

    var cur_table;
    var cur_table_matches;

    var show_or_hide_table = function() {
        if (cur_table) {
            DOM.setStyle(cur_table, "display", cur_table_matches ? "" : "none");
            if (!cur_table_matches) {
                containers_shown--;
            }
        }
    };

    var last_event_row, rows_length = rows.length;
    for (var r = 0; r < rows_length; r++) {
        var row = rows[r];

        if (row.sectionRowIndex === 0) {
            show_or_hide_table();

            cur_table = DOM.getAncestorByClassName(row, "category-container");
            cur_table_matches = false;
        }

        var show_this_row = needle.test(CPANEL.util.get_text_content(row));

        rows[r] = [row, show_this_row];
        if (DOM.hasClass(row, "event-stage")) {
            last_event_row = rows[r];
        } else if (show_this_row) {
            last_event_row[1] = true;
            CPANEL.Y(last_event_row[0]).one(".toggle-link").innerHTML = DOWN_ARROW;
        }

        if (show_this_row) {
            cur_table_matches = true;
        }
    }

    show_or_hide_table();

    for (r = 0; r < rows_length; r++) {
        DOM.setStyle(rows[r][0], "display", (rows[r][1] ? "" : "none"));
    }

    DOM.setStyle("no_hooks_match_message", "display", containers_shown ? "none" : "");

    CPANEL.Y.all("#hooks_section tbody").forEach(stripe_tbody);
}
EVENT.onDOMReady(update_table_search);

function move_up(id, clicked) {
    return move_offset(id, -1, clicked);
}

function move_down(id, clicked) {
    return move_offset(id, 1, clicked);
}

// A generalized function, in case this is ever useful otherwise.
Array.prototype.move_one = function(idx, offset) {
    if (this.length < 2) {
        return 0;
    }
    if (offset === 0) {
        return idx;
    }
    var new_index = (idx + offset) % this.length;
    if (new_index < 0) {
        new_index += this.length;
    }
    var item = this.splice(idx, 1)[0];
    this.splice(new_index, 0, item);
    return new_index;
};

function move_offset(id, offset, clicked) {
    clicked.blur(); // FF 9.0.1 persists the focus outline without this.

    var the_hook = get_hook_by_id(id);
    var hooks = get_hook_and_siblings_by_id(id);
    var hook_ids = hooks.map(function(h) {
        return h.id;
    });

    var cur_index = hook_ids.indexOf(id);
    hook_ids.move_one(cur_index, offset);

    var success = function() {
        hooks.sort_by(function(h) {
            return hook_ids.indexOf(h.id);
        });
        _reorder_rows_by_id(hook_ids);
    };

    var table = DOM.getAncestorByTagName(clicked, "table");
    var overlay = new CPANEL.ajax.Page_Progress_Overlay(null, {
        covers: table,
        status_html: LOCALE.maketext("Reordering hooks …")
    });
    overlay.show();

    CPANEL.api({
        func: "reorder_hooks",
        data: {
            ids: hook_ids.join(",")
        },
        catch_api_errors: true,
        callback: CPANEL.ajax.build_page_callback(success, {
            hide_on_return: overlay
        })
    });
}

function _reorder_rows_by_id(ordered_ids) {
    var last = DOM.get("hook-" + ordered_ids[ordered_ids.length - 1]);

    var tbody = last.parentNode;

    ordered_ids.forEach(function(id, idx) {
        var row = DOM.get("hook-" + id);

        if (row !== last) {
            tbody.removeChild(row);
        }

        var up_link = CPANEL.Y(row).one("a.up-link");
        var down_link = CPANEL.Y(row).one("a.down-link");

        if (idx === 0) {
            DOM.addClass(row, "first-hook");
            up_link.title = LOCALE.maketext("Move this hook to the bottom.");
        } else {
            DOM.removeClass(row, "first-hook");
            up_link.title = LOCALE.maketext("Move this hook up.");
        }

        if (idx === (ordered_ids.length - 1)) {
            DOM.addClass(row, "final-hook");
            down_link.title = LOCALE.maketext("Move this hook to the top.");
        } else {
            DOM.removeClass(row, "final-hook");
            down_link.title = LOCALE.maketext("Move this hook down.");
        }

        if (row !== last) {
            tbody.insertBefore(row, last);
        }
    });
    stripe_tbody(tbody);
}
