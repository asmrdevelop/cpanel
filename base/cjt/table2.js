/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof (CPANEL) === "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including table2.js!");
} else {

    // el: string or DOM object
    // data: array of objects
    // animate_render: boolean
    //
    // columns: array of objects, e.g.:
    // {
    //  key: 'user',                    //required
    //  label: 'Username',              //optional
    //  renderer: function(row,i) {..}  //optional
    // }
    // "renderer" receives the data row and index and must return a String object
    //
    // actions: array of objects { label: "", code: function(row,i) {..} }
    // each function receives the data row and index as its parameters
    CPANEL.table2 = function(table_opts) {
        for (var i in table_opts) {
            this[i] = table_opts[i];
        }

        this.columns = this.columns.map(function(col_data) {
            var key = col_data.key;
            if (!("renderer" in col_data)) {
                col_data.renderer = function(row) {
                    return row[key];
                };
            }
            if (!("label" in col_data)) {
                col_data.label = key;
            }

            return col_data;
        });

        var need_to_render_head = true;
        if ("el" in this) {
            if (typeof this.el === "string") {
                this.id = this.el;
                this.el = DOM.get(this.el);
            } else {
                this.id = this.el.id || DOM.generateId(this.el);
            }
            this.head = this.el.tHead;
            if (!this.head) {
                this.head = document.createElement("thead");
                this.foot = document.createElement("tfoot");
                this.el.insertBefore(this.foot, this.el.firstChild);
                this.el.insertBefore(this.head, this.el.firstChild);
            } else {
                need_to_render_head = false;
            }
            var tBodies = this.el.tBodies;
            if (tBodies && tBodies.length > 0) {
                this.body = tBodies[0];
            } else {
                this.body = document.createElement("tbody");
                this.el.appendChild(this.body);
            }
        } else {
            this.el = document.createElement("table");
            this.id = DOM.generateId(this.el);
            this.head = document.createElement("thead");
            this.body = document.createElement("tbody");
        }

        DOM.addClass(this.el, "cjt-table");

        this.constructor.tables[this.id] = this;
        this._encoded_id = this.id.html_encode();

        if (!("animate_render" in this)) {
            this.animate_render = true;
        }
        this.animate_render = false; // for now, until/if I get it working

        if (need_to_render_head) {
            this.render_head();
        }

        if ("data" in this) {
            this.render();
        }
    };

    // id => JS object
    CPANEL.table2.tables = {};

    YAHOO.lang.augmentObject(CPANEL.table2.prototype, {

        // requires this.data
        render: function() {
            var that = this;

            if ("actions" in this) {
                var actions_html = this.actions.map(function(action, action_index) {
                    return YAHOO.lang.substitute(that._action_item_template, {
                        action_label: action.label.html_encode(),
                        action_index: action_index,
                        table_id: that._encoded_id
                    });
                }).join("");

                this._actions_html = "<ul class='cjt-table-action-list'>" + actions_html + "</ul>";

                this.data.forEach(function(d, i) {
                    that._cached_forms[i] = {};
                });
            }

            // this may be faster combining the reduce() and forEach()
            this.data
                .map(function(row, idx) {
                    return that._generate_row_objects.call(that, row, idx);
                })
                .reduce(function(a, b) {
                    return a.concat(b);
                }, []) // flatten the list
                .forEach(function(row) {
                    that.body.appendChild(row);
                });

            // accommodate touch screens!!
            if (!CPANEL.is_touchscreen && ("actions" in this)) {
                this._show_actions(0);
            }

            if (this.animate_render) {
                Array.prototype.filter.call(this.body.rows, function(r) {
                    return !DOM.hasClass(r, "cjt-table-form-row");
                })
                    .forEach(function(r) {
                        Array.prototype.filter.call(r, CPANEL.animate.slide_down);
                    });
            }
        },
        render_head: function() {
            var that = this;
            var column_headers = this.columns.map(function(col) {
                var th = document.createElement("th");
                th.id = that.id + "-head-cell-" + col.key;
                th.innerHTML = col.label;
                return th;
            });

            // IE can't handle injecting rows via innerHTML
            var the_row = document.createElement("tr");
            the_row.id = this.id + "-head-row";
            the_row.className = "cjt-table-head-row";
            column_headers.forEach(function(h) {
                the_row.appendChild(h);
            });
            this.head.appendChild(the_row);
        },
        render_action: function(action, data_index) {
            var form_cell = this._get_form_cell(data_index);

            // form elements are always wrapped in a div
            var existing_form_contents = form_cell.firstChild;

            if (existing_form_contents) {
                this._cached_forms[data_index][action.label] = existing_form_contents;

                CPANEL.animate.slide_up_and_remove(form_cell.firstChild);

                if ((data_index in this._open_forms) && this._open_forms[data_index] === action.label) {
                    delete this._open_forms[data_index];
                    return;
                }
            }


            var form_div = (data_index in this._cached_forms) && this._cached_forms[data_index][action.label];
            if (!form_div) {
                form_div = document.createElement("div");
                form_div.innerHTML = action.code(this.data[data_index], data_index);
                DOM.addClass(form_div, "cjt-table-form");
                DOM.setStyle(form_div, "display", "none");
            }

            form_cell.appendChild(form_div);
            CPANEL.animate.slide_down(form_div);
            this._open_forms[data_index] = action.label;
        },
        reset: function() {
            for (var open_index in this._open_forms) {
                var form_cell = _get_form_cell(open_index);
                var contents = form_cell.childNodes;
                if (contents) {
                    Array.prototype.forEach.call(contents, CPANEL.animate.slide_up_and_remove);
                }
            }
        },

        // row_index => action label => HTML
        _cached_forms: {},

        // row index => action label
        _open_forms: {},

        _get_form_cell: function(i) {
            return DOM.get(this.id + "-form-cell-" + i);
        },

        _action_item_template: "<li class=\"cjt-table-action-{action_label}\" onclick='CPANEL.table2.tables[\"{table_id}\"].render_action(CPANEL.table2.tables[\"{table_id}\"].actions[{action_index}],{d_index})'>{action_label}</li>",

        _generate_row_objects: function(row_data, row_index) {
            var data_cells = this.columns.map(function(col_data, col_index) {
                var key = col_data.key;
                var cell = document.createElement("td");
                if (this.animate_render) {
                    cell.style.height = "0";
                }
                cell.className = "cjt-table-data-cell-" + col_data.key;
                cell.innerHTML = col_data.renderer(row_data, row_index);
                return cell;
            });

            var stripe_class = row_index % 2 ? "row-odd" : "row-even";
            var row_class = ["cjt-table-data-row", stripe_class];

            var row_events = {};
            if (this._actions_html) {
                var that = this;
                if (CPANEL.is_touchscreen) {
                    row_events.ontouchstart = function() {
                        that._toggle_actions(row_index);
                    };
                } else {
                    row_events.onmouseover = function() {
                        that._show_actions(row_index);
                    };
                }
                row_class.push("cjt-table-data-row-with-actions");
            }

            var main_row = document.createElement("tr");
            main_row.id = this.id + "-data-row-" + row_index;
            main_row.className = row_class.join(" ");
            data_cells.forEach(function(c) {
                main_row.appendChild(c);
            });

            var rows = [main_row];

            if (this._actions_html) {
                var click_row = document.createElement("tr");
                click_row.id = this.id + "-click-row-" + row_index;
                click_row.className = "cjt-table-click-row " + stripe_class;
                var click_row_cell = document.createElement("td");
                click_row_cell.colSpan = 99;
                click_row_cell.innerHTML = YAHOO.lang.substitute(this._actions_html + "", {
                    "d_index": row_index
                });
                click_row.appendChild(click_row_cell);

                var form_row = document.createElement("tr");
                form_row.id = this.id + "-form-row-" + row_index;
                form_row.className = "cjt-table-form-row " + stripe_class;
                var form_row_cell = document.createElement("td");
                form_row_cell.id = this.id + "-form-cell-" + row_index;
                form_row_cell.colSpan = 99;
                form_row.appendChild(form_row_cell);

                rows.push(click_row, form_row);
            }

            // assign events as needed
            for (var ev in row_events) {
                rows.forEach(function(r) {
                    r[ev] = row_events[ev];
                });
            }

            return rows;
        },

        _shown_actions_index: null,
        _show_actions: function(row_index) {
            if (row_index !== this._shown_actions_index) {
                this._hide_actions(this._shown_actions_index);
                DOM.addClass(this.id + "-click-row-" + row_index, "actions_visible");
                this._shown_actions_index = row_index;
            }
        },
        _hide_actions: function(row_index) {
            DOM.removeClass(this.id + "-click-row-" + row_index, "actions_visible");
        },
        _toggle_actions: function(row_index) {
            if (row_index === this._shown_actions_index) {
                this._hide_actions(row_index);
                this._shown_actions_index = null;
            } else {
                this._show_actions(row_index);
            }
        },

        _: true // does nothing
    });


    (function() {
        var _stylesheet = [
            [".cjt-table-form-cell", "padding: 0px "],
            [".cjt-table-action", "float:left; cursor:pointer"],
            [".cjt-table-action-list", "visibility:hidden; list-style:none; padding:0; margin:0"],
            [".cjt-table-click-row.actions_visible ul", "visibility:visible"]
        ];
        var inserter;
        var first_stylesheet = document.styleSheets[0];
        if (!first_stylesheet) {
            var new_stylesheet = document.createElement("style");
            document.head.appendChild(new_stylesheet);
            first_stylesheet = document.styleSheets[0];
        }
        if ("insertRule" in first_stylesheet) { // W3C DOM
            _stylesheet.forEach(function(rule) {
                first_stylesheet.insertRule(rule[0] + " {" + rule[1] + "}", 0);
            });
        } else { // IE
            _stylesheet.forEach(function(rule) {
                first_stylesheet.addRule(rule[0], rule[1], 0);
            });
        }
    })();

    CPANEL.table2.Tree = function(name) {
        this.name = name;
    };

}
