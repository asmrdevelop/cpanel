/*
    # base/cjt/datatable.js                           Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// Extensions to YUI DataTable
// Requires DataSource and Paginator

(function() {

    var DT = YAHOO.widget.DataTable;

    // This fixes issue #2529475, which wasn't addressed in YUI 2.9.0 and
    // thus will remain broken in YUI 2.
    if (!YAHOO.widget.Paginator._fixed_2529475) {
        var Dom = DOM;
        var Paginator = YAHOO.widget.Paginator;

        YAHOO.widget.Paginator._fixed_2529475 = true;

        YAHOO.widget.Paginator.prototype.updateVisibility = function(e) {
            var alwaysVisible = this.get("alwaysVisible"),
                totalRecords, visible, rpp, rppOptions, i, len, opt;

            if (!e || e.type === "alwaysVisibleChange" || !alwaysVisible) {
                totalRecords = this.get("totalRecords");
                visible = true;
                rpp = this.get("rowsPerPage");
                rppOptions = this.get("rowsPerPageOptions");

                if (isArray(rppOptions)) {
                    for (i = 0, len = rppOptions.length; i < len; ++i) {
                        opt = rppOptions[i];

                        // account for value 'all'
                        if (lang.isNumber(opt.value || opt)) { // THIS IS THE FIX.
                            rpp = Math.min(rpp, (opt.value || opt));
                        }
                    }
                }

                if (totalRecords !== Paginator.VALUE_UNLIMITED &&
                    totalRecords <= rpp) {
                    visible = false;
                }

                visible = visible || alwaysVisible;

                for (i = 0, len = this._containers.length; i < len; ++i) {
                    Dom.setStyle(this._containers[i], "display",
                        visible ? "" : "none");
                }
            }
        };
    }


    if (!DT._has_message_last_row) {
        DT._has_message_last_row = true;

        var _show = DT.prototype.showTableMessage;
        DT.prototype.showTableMessage = function() {
            if (this.getTbodyEl().rows.length === 0) {
                DOM.addClass(this.getMsgTdEl().parentNode, "cjt_last_row");
            }
            return _show.apply(this, arguments);
        };
        var _hide = DT.prototype.hideTableMessage;
        DT.prototype.hideTableMessage = function() {
            DOM.removeClass(this.getMsgTdEl().parentNode, "cjt_last_row");
            return _hide.apply(this, arguments);
        };
    }

    // Remove hidden table message text so copy/paste doesn't show it.
    // YUI 2.9.0 did not fix this; it likely will remain broken in YUI 2.
    if (!DT._fixed_2529233_message_text) {
        DT._fixed_2529233_message_text = true;

        var _hideTableMessage = DT.prototype.hideTableMessage;
        DT.prototype.hideTableMessage = function() {
            var ret = _hideTableMessage.apply(this, arguments);
            this.getMsgTdEl().firstChild.innerHTML = "";
            return ret;
        };
    }

    if (!DT.fixed_reorderColumn_class_bug_2529435) {
        DT.fixed_reorderColumn_class_bug_2529435 = true;
        var _reorder = DT.prototype.reorderColumn;
        DT.prototype.reorderColumn = function(col, idx) {
            var old_idx = col.getIndex();
            var cols_last_i = this.getColumnSet().keys.length - 1;

            var ret = _reorder.apply(this, arguments);

            if (ret) {
                var changed_first = (idx === 0) || (old_idx === 0);
                var changed_last = (idx === cols_last_i) || (old_idx === cols_last_i);

                var rows, rows_length, cur_row, row_cells, old_cell, cur_cell;
                var class_first = DT.CLASS_FIRST,
                    class_last = DT.CLASS_LAST;
                if (changed_first || changed_last) {
                    rows = this.getTbodyEl().rows;
                    rows_length = rows.length;
                    for (var r = 0; cur_row = rows[r]; r++) {
                        row_cells = cur_row.cells;
                        cur_cell = row_cells[idx];

                        // dragged a column to be first
                        if (idx === 0) {
                            old_cell = row_cells[1];

                            // dragged column was last
                            if (old_idx === cols_last_i) {
                                cur_cell.className = cur_cell.className.replace(class_last, class_first);
                            } else {
                                cur_cell.className += " " + class_first;
                            }

                            if (cols_last_i === 1) {
                                old_cell.className = old_cell.className.replace(class_first, class_last);
                            } else {
                                DOM.removeClass(old_cell, class_first);
                            }
                        } else if (old_idx === 0) { // dragged a column that *was* first
                            old_cell = row_cells[0];

                            // dragged column is now last
                            if (idx === cols_last_i) {
                                cur_cell.className = cur_cell.className.replace(class_first, class_last);
                            } else {
                                DOM.removeClass(cur_cell, class_first);
                            }

                            if (cols_last_i === 1) {
                                old_cell.className = old_cell.className.replace(class_last, class_first);
                            } else {
                                old_cell.className += " " + class_first;
                            }
                        } else if (idx === cols_last_i) { // dragged a column to be last
                            cur_cell.className += " " + class_last;
                            DOM.removeClass(row_cells[cols_last_i], class_last);
                        } else if (old_idx === cols_last_i) { // dragged a column that *was* last
                            row_cells[cols_last_i].className += " " + class_last;
                            DOM.removeClass(cur_cell, class_last);
                        }
                    }
                }
            }

            return ret;
        };
    }

    // add max_width and fixed_width DataTable properties,
    // and make column resizing not affect the table width
    // (except for the last column, of course)
    if (!DT._has_max_width_and_fixed_width) {
        DT._has_max_width_and_fixed_width = true;

        var _initAttributes = DT.prototype.initAttributes;
        DT.prototype.initAttributes = function() {
            _initAttributes.apply(this, arguments);

            var that = this;

            // the last column cannot have an active resize handle
            var _fixed_width_reorder_listener = function(oArgs) {
                var columns = that.getColumnSet().flat;
                for (var c = 0; c < columns.length; c++) {
                    var cur_resizer_el = columns[c].getResizerEl();
                    if (cur_resizer_el) {
                        var th_cursor = DOM.getStyle(columns[c].getThEl(), "cursor");
                        cur_resizer_el.style.cursor = (c === columns.length - 1) ? th_cursor : "";
                    }
                }
            };

            this.setAttributeConfig("max_width", {
                value: null,
                validator: YAHOO.lang.isNumber
            });
            this.setAttributeConfig("fixed_width", {
                value: null,
                method: function(new_fixed_width) {
                    if (new_fixed_width) {
                        this.subscribe("initEvent", _fixed_width_reorder_listener);
                        this.subscribe("columnReorderEvent", _fixed_width_reorder_listener);
                    } else {
                        this.unsubscribe("columnReorderEvent", _fixed_width_reorder_listener);
                    }
                }
            });
        };

        // We need a way of identifying in CSS which drag handles are going to be
        // inactive when a table has fixed_width.
        //
        // The _initResizeableColumns method is private...
        // but it should be stable for YUI 2 (which should have no more releases).
        var _irc = DT.prototype._initResizeableColumns;
        DT.prototype._initResizeableColumns = function() {
            _irc.apply(this, arguments);

            var cols = this.getColumnSet().keys;
            var cur_col, next_col;
            for (var c = 0;
                (cur_col = cols[c]) && (next_col = cols[c + 1]); c++) {
                if (cur_col.resizeable) {
                    if (next_col.resizeable) {
                        DOM.removeClass(cur_col._elResizer, "inactive");
                    } else {
                        DOM.addClass(cur_col._elResizer, "inactive");
                    }
                }
            }
        };

        // we want the datatable not to expand unless the last column is expanded
        var _onMouseDown = YAHOO.util.ColumnResizer.prototype.onMouseDown;
        YAHOO.util.ColumnResizer.prototype.onMouseDown = function() {
            _onMouseDown.apply(this, arguments);

            // for all columns besides the last one,
            // adjust the next column equally to the first
            var this_col = this.column;
            var datatable = this.datatable;
            var columns = datatable.getColumnSet().flat;
            var col_index = this_col.getKeyIndex();

            var this_col_is_rightmost = (columns.length === col_index + 1);

            var custom_setColumnWidth;

            var _setColumnWidth = datatable.setColumnWidth;

            if (!this_col_is_rightmost) {
                var other_column = columns[col_index + 1];
                while (other_column && (other_column.hidden || !other_column.resizeable)) {
                    col_index++;
                    other_column = columns[col_index + 1];
                }

                if (other_column) {
                    var other_column_head_cell_liner = other_column.getThLinerEl();
                    var other_column_n_liner_padding =
                        (parseInt(DOM.getStyle(other_column_head_cell_liner, "paddingLeft")) || 0) + (parseInt(DOM.getStyle(other_column_head_cell_liner, "paddingRight")) || 0);
                    var other_column_start_width = other_column_head_cell_liner.offsetWidth - other_column_n_liner_padding;

                    var col_max_width = other_column_start_width + this.startWidth - this.nLinerPadding - 1;
                    custom_setColumnWidth = function(col, width) {
                        if (width <= col_max_width) {
                            _setColumnWidth.call(this, col, width);
                            _setColumnWidth.call(this, other_column, col_max_width - width + 1);
                        }
                    };
                } else {

                    // abort drag if this is not the rightmost column,
                    // fixed_width is enabled,
                    // and there are no other columns to adjust
                    return this.datatable.get("fixed_width") ? false : true;
                }
            } else if (!this.datatable.get("fixed_width")) {
                var table_max_width = this.datatable.get("max_width");
                if (table_max_width) {
                    var max_col_width = this.startWidth + table_max_width - (parseInt(DOM.getStyle(this.datatable.getTableEl(), "width")) || 0) - this.nLinerPadding;

                    custom_setColumnWidth = function(col, width) {
                        if (width > max_col_width) {
                            width = max_col_width;
                        }
                        _setColumnWidth.call(this, col, width);
                    };

                }
            } else {
                return false;
            }

            if (custom_setColumnWidth) {
                var has_own = datatable.hasOwnProperty("setColumnWidth");
                datatable.setColumnWidth = custom_setColumnWidth;
                datatable.subscribe("columnResizeEvent", function() {
                    this.unsubscribe("columnResizeEvent", arguments.callee);
                    if (has_own) {
                        datatable.setColumnWidth = _setColumnWidth;
                    } else {
                        delete datatable.setColumnWidth;
                    }
                });
            }
        };
    }

    // relative_widths is a hash of relative content widths that will be scaled
    // such that the table's offsetWidth matches the desired_width.
    // Within relative_widths an item can be either a number primitive or
    // { value: number, absolute: boolean }. Actual Number objects would be
    // well-suited for attaching the "absolute" property", but these were decided
    // against because they are not widely used and present behavioral oddities,
    // e.g. (new Number(0)) === true
    // This will also check for a fixed_width property on a Column and, if there is
    // no relative_width for that column, will leave that column the
    // width that it currently is.
    DT.prototype.set_width = function(desired_width, relative_widths) {
        if (!desired_width) {
            desired_width = this.getTableEl().offsetWidth;
        }
        var cols = this.getColumnSet().flat.filter(function(c) {
            return !c.hidden;
        });
        var cols_length = cols.length;

        // these are only used if !relative_widths
        var relative_content_widths = {};
        var total_relative_content_width = 0;
        var total_fixed_content_width = 0;

        var total_padding = 0;
        var total_border_widths = 0;
        var fixed_column_widths = {};
        var cur_col;
        for (var c = 0; cur_col = cols[c]; c++) {
            var liner_el = cur_col.getThLinerEl();
            var resize_liner_el = liner_el.parentNode;

            var liner_padding_width = (parseFloat(DOM.getStyle(liner_el, "padding-left")) || 0) + (parseFloat(DOM.getStyle(liner_el, "padding-right")) || 0);

            total_padding += liner_padding_width;

            // Firefox/Gecko likes to report fractional values
            // for computed CSS "width", so we compute content width here
            // rather than reading computed style.
            // Also, this really should use clientWidth, but older IE versions
            // sometimes errantly return 0 for clientWidth.
            // We can safely assume, though, that liner elements have no border.
            if (!relative_widths) {
                var liner_content_width = liner_el.offsetWidth - liner_padding_width;

                // see above about IE and clientWidth
                var th_content_width = resize_liner_el.offsetWidth; -(parseFloat(DOM.getStyle(resize_liner_el, "padding-left")) || 0) - (parseFloat(DOM.getStyle(resize_liner_el, "padding-right")) || 0);

                // extra width = cell content outside the liner
                var extra_width = th_content_width - liner_el.offsetWidth;

                if (!cur_col.fixed_width) {
                    relative_content_widths[cur_col.key] = liner_content_width + extra_width;
                    total_relative_content_width += liner_content_width + extra_width;
                }
            }

            var th_el = cur_col.getThEl();

            // see above about IE and clientWidth
            var clientWidth = th_el.clientWidth;
            if (clientWidth) {
                total_border_widths += th_el.offsetWidth - th_el.clientWidth;
            } else {
                total_border_widths +=
                    (parseFloat(DOM.getStyle(th_el, "border-left-width")) || 0) + (parseFloat(DOM.getStyle(th_el, "border-right-width")) || 0);
            }

            if (cur_col.fixed_width && ("width" in cur_col)) {
                total_fixed_content_width += fixed_column_widths[c] = parseFloat(cur_col.width);
                if (relative_widths && !relative_widths[cur_col.key]) {
                    relative_widths[cur_col.key] = {
                        absolute: true,
                        value: fixed_column_widths[c]
                    };
                }
            }
        }

        // this is how much the content widths need to take up in total
        // so that the table takes up the desired width
        var total_available_content_width = desired_width - total_border_widths - total_padding;

        // precompute the widths so that we can compensate for rounding problems,
        // e.g. rounded widths not all adding up as they should
        var new_widths = [];
        var total_new_widths = 0;
        var cur_fixed;
        if (relative_widths) {
            var total_relative_width = 0;
            var total_available_relative_width = total_available_content_width;
            var cur_key;
            for (var w = 0; cur_col = cols[w]; w++) {
                cur_key = cur_col.key;
                if (!relative_widths[cur_key]) {
                    relative_widths[cur_key] = cols[w].width || parseFloat(DOM.getStyle(cur_col.getThLinerEl(), "width"));
                }

                if (relative_widths[cur_key].absolute) {
                    fixed_column_widths[w] = cur_fixed = relative_widths[cur_key].value || relative_widths[cur_key];
                    total_available_relative_width -= cur_fixed;
                } else {
                    total_relative_width += relative_widths[cur_key].value || relative_widths[cur_key];
                }
            }

            for (var c = 0; cur_col = cols[c]; c++) {
                cur_key = cur_col.key;
                var cur_width = relative_widths[cur_key].value || relative_widths[cur_key];
                if (!relative_widths[cur_key].absolute) {
                    cur_width = parseInt(.5 + total_available_relative_width * cur_width / total_relative_width);
                }
                new_widths.push(cur_width);
                total_new_widths += cur_width;
            }
        } else {
            var total_available_relative_width = total_available_content_width - total_fixed_content_width;

            var cur_width;
            for (var c = 0; cur_col = cols[c]; c++) {
                if (cur_col.fixed_width) {
                    cur_width = fixed_column_widths[c];
                } else {
                    cur_width = parseInt(.5 + total_available_relative_width * relative_content_widths[cur_col.key] / total_relative_content_width);
                }
                new_widths.push(cur_width);
                total_new_widths += cur_width;
            }
        }

        if (total_new_widths !== total_available_content_width) {

            // Sort the column indexes by their new_width value,
            // then add/subtract 1 to/from each new_width until the deficit is 0.
            // If the table needs to be bigger, then add to the smallest rows;
            // otherwise, subtract from the largest.
            // We do this by controlling the sort direction of the indexes array.
            var sort_xformer = function(i) {
                return new_widths[i];
            };

            var sorted_indexes = [];
            for (var i = 0; i < cols_length; i++) {
                sorted_indexes.push(i);
            }

            var i = 0;

            var deficit = total_available_content_width - total_new_widths;

            if (deficit > 0) {
                sorted_indexes.sort_by(sort_xformer);
                while (deficit > 0) {
                    if (!(sorted_indexes[i] in fixed_column_widths)) {
                        new_widths[sorted_indexes[i]]++;
                        deficit--;
                    }
                    i++;
                    if (i === cols_length) {
                        i = 0;
                    }
                }
            } else {
                sort_xformer.reverse = true;
                sorted_indexes.sort_by(sort_xformer);
                while (deficit < 0) {
                    if (!(sorted_indexes[i] in fixed_column_widths)) {
                        new_widths[sorted_indexes[i]]--;
                        deficit++;
                    }
                    i++;
                    if (i === cols_length) {
                        i = 0;
                    }
                }
            }
        }

        var table_style = this.getTableEl().style;
        table_style.visibility = "hidden";
        table_style.width = "auto";
        for (var c = 0; c < cols_length; c++) {
            this.setColumnWidth(this.getColumn(cols[c].key), new_widths[c]);
        }
        table_style.visibility = "";
    };

    // Determine default widths based on the pixel width
    // of its header's longest string (in chars) -- or,
    // if a column has "size_to_data", the pixel width of the longest string
    // in the column (in chars).
    DT.prototype.size_columns = function() {

        // When NVData does not provide usable column widths,
        // give each column a default width based on the pixel width
        // of its header's longest string.
        relative_widths = {};
        var column_count = this.getColumnSet().flat.length;
        var test_span = document.createElement("span");
        test_span.style.position = "absolute";
        test_span.style.visibility = "hidden";

        for (var c = 0; c < column_count; c++) {
            var col = this.getColumn(c);
            var cur_liner_el = col.getThLinerEl();
            var longest_word = CPANEL.util.get_text_content(cur_liner_el).split(/\s+/).sort_by("!length")[0];
            CPANEL.util.set_text_content(test_span, longest_word);
            cur_liner_el.appendChild(test_span);
            var min_header_width = test_span.offsetWidth;
            cur_liner_el.removeChild(test_span);

            if (col.default_width_is_absolute) {
                var str;
                var length_cache = {};
                var longest_cell = this.getDataSource().liveData
                    .map(function(r) {
                        str = String(r[col.key]);
                        if (str in length_cache) {
                            return length_cache[str];
                        }
                        return length_cache[str] = str ? str.split(/\s+/).sort_by("!length")[0] : 0;
                    })
                    .sort_by("!length")[0];
                var cell_liner = this.getTdLinerEl({
                    record: this.getRecord(0),
                    column: col
                });
                CPANEL.util.set_text_content(test_span, longest_cell);
                cell_liner.appendChild(test_span);
                var max_data_width = test_span.offsetWidth;
                cell_liner.removeChild(test_span);

                var absolute_width = {
                    value: 1 + Math.max(min_header_width, max_data_width),
                    absolute: true
                };
                relative_widths[col.key] = absolute_width;
            } else {
                relative_widths[col.key] = min_header_width;
            }
        }

        return relative_widths;
    };


    // Allow a certain number of columns on the left or right to be
    // non-draggable.
    //
    // This necessitates messing with private stuff...but YUI 2.9.0 should be
    // pretty fixed (as of May 2011); the team has stated publicly that they
    // intend no further releases of YUI 2.
    // Anyhow, after DataTable creates all of the drag stuff for each column,
    // we now go in and undo that work for the appropriate columns.
    // It's less than ideal; hopefully YUI 3 will include this ability built-in.
    var _ia = DT.prototype.initAttributes;
    DT.prototype.initAttributes = function(oConfigs) {
        _ia.apply(this, arguments);
        this.setAttributeConfig("left_nondraggable_columns", {
            value: 0,
            validator: YAHOO.lang.isNumber
        });
        this.setAttributeConfig("right_nondraggable_columns", {
            value: 0,
            validator: YAHOO.lang.isNumber
        });
    };
    var _idc = DT.prototype._initDraggableColumns;
    DT.prototype._initDraggableColumns = function() {
        _idc.apply(this, arguments);

        var tree = this._oColumnSet.tree[0],
            len = tree.length;
        var left = this.get("left_nondraggable_columns");
        var right = this.get("right_nondraggable_columns");
        for (var i = 0; i < len; i++) {
            if ((i < left) || (i > len - right - 1)) {
                DOM.removeClass(tree[i].getThEl(), DT.CLASS_DRAGGABLE);
                tree[i]._dd.unreg();
                delete tree[i]._dd;
            }
        }
    };

    // So that set_width will still see fixed_width in a Column
    // after a column reorder.
    var _get_def = YAHOO.widget.Column.prototype.getDefinition;
    YAHOO.widget.Column.prototype.getDefinition = function() {
        var def = _get_def.apply(this, arguments);
        def.fixed_width = this.fixed_width;
        return def;
    };


    // config parameters:
    //  search_box        - REQUIRED HTML element or ID
    //  searchable_fields - array
    //  default_sortedBy  - see sortedBy config parameter; use this if the data
    //                      from the DataSource is always sorted a certain way

    var IGNORE_KEY_CODES = {
        9: true, // tab
        16: true, // shift
        17: true, // ctrl
        18: true // alt
    };

    var _SearchableDataTable = function() {
        _SearchableDataTable.superclass.constructor.apply(this, arguments);
        var dt = this;
        var ds = this.getDataSource();

        this._search_box = YAHOO.util.Dom.get(this.get("search_box"));

        var search_timeout = null;
        EVENT.on(this._search_box, "keyup", function(e) {
            clearTimeout(search_timeout);
            if (!(e.keyCode in IGNORE_KEY_CODES)) {
                search_timeout = setTimeout(function() {
                    dt.do_text_search();
                }, 500);
            }
        });

        if (this.get("dynamicData")) {
            this._set_generateRequest();
        } else {

            // for filtering
            var _concatenated_values = [];
            var searchable_fields = (this.get("searchable_fields") || this.getColumnSet().keys.map(function(c) {
                return c.key;
            }));
            var searchable_fields_length = searchable_fields.length;
            var liveData = ds.liveData;
            var liveData_length = liveData.length;
            for (var ld = 0; ld < liveData_length; ld++) {
                var search_values = [];
                var row = liveData[ld];
                for (var v = 0; v < searchable_fields_length; v++) {
                    search_values.push(row[searchable_fields[v]]);
                }
                _concatenated_values.push(search_values.join("\n").toLowerCase());
            }

            ds.subscribe("responseParseEvent", function(oArgs) {
                var req = oArgs.request,
                    resp = oArgs.response;

                // filter
                if (req) {
                    var matches = [];
                    req = req.toLowerCase();

                    var all_results = resp.results;
                    var resp_length = all_results.length;
                    var __concatenated_values = _concatenated_values;
                    for (var r = 0; r < resp_length; r++) {
                        if (__concatenated_values[r].indexOf(req) !== -1) {
                            matches.push(all_results[r]);
                        }
                    }

                    resp.results = matches;
                }
            });

            this.subscribe("dataReturnEvent", function(oArgs) {
                var req = oArgs.request,
                    resp = oArgs.response,
                    pay = oArgs.payload;

                // restore sort
                var need_to_sort = resp.results.length > 1;

                var cur_sort, sort_column;
                if (need_to_sort) {
                    cur_sort = this.getState().sortedBy;
                    sort_column = cur_sort && (cur_sort.column || this.getColumn(cur_sort.key));

                    need_to_sort = sort_column;
                }

                // forego sorting if it would duplicate the DataSource sort
                if (need_to_sort) {
                    var ds_sort = this.get("default_sortedBy");

                    need_to_sort = !ds_sort || cur_sort.key !== ds_sort.key || cur_sort.dir !== ds_sort.dir;
                }

                if (need_to_sort) {
                    if (resp.results === liveData) {
                        resp.results = liveData.slice(0); // so sorts won't affect liveData
                    }

                    var sort_func = sort_column.sortOptions && sort_column.sortOptions.sortFunction;

                    // Get the field to sort
                    var sField = (sort_column.sortOptions && sort_column.sortOptions.field) || sort_column.field;
                    var desc = ((cur_sort.dir === DT.CLASS_DESC) ? true : false);

                    if (sort_func) {
                        resp.results.sort(function(a, b) {
                            return sort_func(a, b, desc, sField);
                        });
                    } else {
                        resp.results.sort_by(desc ? "!" + sField : sField);
                    }
                }

                // reset pagination to first page
                if (pay) {
                    if (pay.pagination) {
                        pay.pagination.recordOffset = 0;
                    } else {
                        pay.pagination = {
                            recordOffset: 0
                        };
                    }
                } else {
                    oArgs.payload = {
                        pagination: {
                            recordOffset: 0
                        }
                    };
                }
            });
        }

        this.subscribe("dynamicDataChange", this._set_generateRequest);
    };

    EVENT.throwErrors = true;
    YAHOO.extend(_SearchableDataTable, DT, {
        initAttributes: function(confs) {
            confs = confs || {};
            _SearchableDataTable.superclass.initAttributes.call(this, confs);

            this.setAttributeConfig("search_box", {
                value: ""
            });
            this.setAttributeConfig("searchable_fields", {
                value: null
            });
            this.setAttributeConfig("default_sortedBy", {
                value: ""
            });
            this.setAttributeConfig("api_request_prototype", {
                value: {}
            });
        },

        _set_generateRequest: function() {
            if (this.get("dynamicData")) {
                var func = _make_generateRequest_func(this.get("api_request_prototype"));
                this.set("generateRequest", func);
            } else {
                this.resetValue("generateRequest");
            }
        },

        _last_query: null,
        _search_box: null,
        _last_local_search: null, // only used if !dynamicData
        _search_box: null,

        getState: function() {
            var state = DT.prototype.getState.apply(this, arguments);
            state.search = this._search_box && this._search_box.value.trim();
            return state;
        },

        do_text_search: function(query, keep_pagination) {
            var state = this.getState();
            var callback = {
                success: this.onDataReturnReplaceRows,
                scope: this,
                argument: state
            };

            if (this.get("dynamicData")) {
                if (!keep_pagination) {
                    state.pagination.recordOffset = 0;
                }
                var request = this.get("generateRequest")(state, this);
                this.getDataSource().sendRequest(request, callback);
                this.showTableMessage(this.get("MSG_LOADING"));
            } else {
                if (!query) {
                    query = this._search_box && this._search_box.value.trim();
                }
                if (query !== this._last_local_search) {
                    this.getDataSource().sendRequest(query, callback);
                    this._last_local_search = query;
                }
            }
        },

        refresh_page: function() {
            return this.do_text_search(null, true);
        }
    });

    var _make_generateRequest_func = function(request_obj_prototype) {
        return function(dt_state, dt) {
            var request_obj;
            if (request_obj_prototype instanceof Function) {
                request_obj = new request_obj_prototype();
            } else {
                request_obj = {};
                YAHOO.lang.augmentObject(request_obj, request_obj_prototype);
            }

            var api_data = {};
            if (dt_state.sortedBy) {
                var sort = (dt_state.sortedBy.dir === DT.CLASS_DESC) ? "!" : "";
                sort += dt_state.sortedBy.key;
                if (dt.getDataSource().get_field_parser(dt_state.sortedBy.key) === "number") {
                    sort = [sort, "numeric"];
                }
                api_data.sort = [sort];
            }
            if (dt_state.search) {
                api_data.filter = [
                    ["*", "contains", dt_state.search]
                ];
            }
            if (dt_state.pagination) {
                api_data.paginate = {
                    start: dt_state.pagination.recordOffset,
                    size: dt_state.pagination.rowsPerPage
                };
            }

            request_obj.api_data = api_data;

            return CPANEL.api.construct_query(request_obj);
        };
    };

    // nvdata    - An initial value for the NVData object (stored as JSON)
    // default_rowsPerPage

    var _Standard_Table = function(id, cols, ds, opts) {
        var nvdata = opts && opts.nvdata || {};

        if (cols && opts && opts.actions) {
            var actions = opts.actions;
            var a, cur_link, link;
            var link_prototypes = actions.map(function(a) {
                cur_link = document.createElement("a");
                cur_link.className = "cjt_table_action_link";
                cur_link.href = "javascript:void(0)";
                CPANEL.util.set_text_content(cur_link, a.label);
                return cur_link;
            });
            var frag = document.createDocumentFragment();
            var new_link;
            var actions_formatter = function(cell, rec) {
                for (a = 0; cur_link = link_prototypes[a]; a++) {
                    new_link = cur_link.cloneNode(true);
                    EVENT.on(new_link, "click", actions[a].handler, rec);
                    frag.appendChild(new_link);
                }
                cell.appendChild(frag);
            };

            var actions_col = {
                key: "actions",
                label: LEXICON.actions,
                formatter: actions_formatter,
                resizeable: false,
                sortable: false
            };

            if (opts.right_nondraggable_columns) {
                opts.right_nondraggable_columns++;
            } else {
                opts.right_nondraggable_columns = 1;
            }

            cols.push(actions_col);
        }

        // we allow 0 as a shorthand for "all"
        var rpp_opts = opts.rows_per_page_options || [25, 100, 150, 0];

        var rows_per_page = nvdata.rows_per_page;
        if (typeof rows_per_page === "undefined") {
            rows_per_page = rpp_opts[0].value || rpp_opts[0];
        }

        var paginator = new YAHOO.widget.Paginator({
            alwaysVisible: false,
            firstPageLinkLabel: LEXICON.first,
            previousPageLinkLabel: LEXICON.previous,
            nextPageLinkLabel: LEXICON.next,
            lastPageLinkLabel: LEXICON.last,
            rowsPerPage: rows_per_page,

            //        template: YAHOO.widget.Paginator.TEMPLATE_DEFAULT + " {JumpToPageDropdown}",
            pageLinks: 5,
            containers: [id + "_top_paginator", id + "_bottom_paginator"]
        });

        paginator.setAttributeConfig("rowsPerPage", {
            getter: function(attr, val) {
                return Number(val) || this.getTotalRecords();
            }
        });

        // defaults for the StandardTable instance
        if (!opts) {
            opts = {};
        }
        YAHOO.lang.augmentObject(opts, {
            MSG_LOADING: CPANEL.icons.ajax + "&nbsp;" + LEXICON.loading,
            MSG_EMPTY: LEXICON.no_records,
            paginator: paginator,
            search_box: id + "_search_box",
            fixed_width: true,
            initialLoad: false,
            draggableColumns: !!YAHOO.util.DD
        }, true); // for now, enforce these defaults


        // Per request from Design, we are foregoing use of YUI Paginator's
        // page size dropdown selector and using a custom-rolled one; ergo
        // rows_per_page_options instead of YUI's rowsPerPageOptions.
        var page_size_changer = DOM.get(id + "_page_size_changer");
        if (page_size_changer) {

            var len = rpp_opts.length;
            var page_size_links = [];
            var clicked_page_size_link;
            for (var c = 0; c < len; c++) {
                var cur_size = rpp_opts[c];
                var label, value;
                if (typeof cur_size === "object") {
                    value = parseInt(cur_size.value);
                    label = cur_size.text || value || LEXICON.all;
                } else {
                    label = cur_size || LEXICON.all;
                    value = parseInt(cur_size);
                }

                var new_link = document.createElement("a");
                CPANEL.util.set_text_content(new_link, label);
                var classes = [];
                if (c === 0) {
                    classes.push("first");
                } else if (len - c === 1) {
                    classes.push("last");
                }
                if (value === rows_per_page) {
                    classes.push("current");
                    clicked_page_size_link = new_link;
                }
                new_link.className = classes.join(" ");

                (function() {
                    var this_value = value;
                    EVENT.on(new_link, "click", function(e) {
                        if (clicked_page_size_link !== this) {
                            DOM.removeClass(clicked_page_size_link, "current");
                            DOM.addClass(this, "current");
                            clicked_page_size_link = this;
                            paginator.all_records_shown = !this_value;
                            paginator.setRowsPerPage(this_value || paginator.getTotalRecords());
                        }
                    });
                })();

                page_size_changer.appendChild(new_link);
                page_size_links.push(new_link);
            }

            paginator.subscribe("render", function() {
                page_size_changer.style.display = "";
            });

            paginator.subscribe("rowsPerPageChange", paginator.updateVisibility, paginator, true);

            paginator.subscribe("totalRecordsChange", function(e) {
                var total = this.getTotalRecords();

                CPANEL.util.set_text_content(id + "_matches_count", LOCALE.maketext("[quant,_1,record,records] match.", total));

                var rpp = this.get("rowsPerPage");

                for (i = 0, len = rpp_opts.length; i < len; ++i) {
                    opt = rpp_opts[i];
                    opt = opt.value || opt;

                    // account for values 0 and 'all'
                    if (opt && YAHOO.lang.isNumber(opt)) {
                        rpp = Math.min(rpp, opt);
                    }
                }

                page_size_changer.style.visibility = (total > rpp) ? "" : "hidden";
            });
        }

        if (nvdata.column_sort) {
            sortedBy = nvdata.column_sort;
            sortedBy.dir = DT[(sortedBy.dir === "asc") ? "CLASS_ASC" : "CLASS_DESC"];
            opts.sortedBy = sortedBy;
        }
        if (nvdata.column_order) {
            cols.sort_by(function(c) {
                return nvdata.column_order.indexOf(c.key);
            });
        }
        if (nvdata.hidden_columns) {
            cols.forEach(function(c) {
                c.hidden = !!nvdata.hidden_columns[c.key];
            });
        }

        _Standard_Table.superclass.constructor.call(this, id + "_container", cols, ds, opts);


        this.subscribe("columnReorderEvent", function(column_oldIndex) {
            this.get("nvdata").column_order = this.getColumnSet().keys.map(function(c) {
                return c.key;
            });
            this._save_nvdata();
        });
        this.subscribe("columnResizeEvent", function() {
            this._save_column_widths();
        });
        this.subscribe("columnSortEvent", function(column_dir) {
            dir = (column_dir.dir === DT.CLASS_ASC) ? "asc" : "desc";
            this.get("nvdata").column_sort = {
                key: column_dir.column.key,
                dir: dir
            };
            this._save_nvdata();
        });
        this.subscribe("columnShowEvent", function resizer(oArgs) {
            this.set_width(this._initial_width);
            this._update_nvdata_hidden_columns();
            this._save_column_widths();
        });
        this.subscribe("columnHideEvent", function resizer() {
            this.set_width(this._initial_width);
            this._update_nvdata_hidden_columns();
            this._save_column_widths();
        });

        var initial_width = this.getTableEl().offsetWidth;
        this._initial_width = initial_width;

        this.subscribe("beforeRenderEvent", function hider() {
            this.unsubscribe("beforeRenderEvent", hider);
            DOM.setStyle(id + "_container", "visibility", "hidden");
        });

        this.subscribe("postRenderEvent", function postrender() {
            this.unsubscribe("postRenderEvent", postrender);

            var search_placeholder_overlay = new CPANEL.widgets.Text_Input_Placeholder(
                id + "_search_box",
                LEXICON.search
            );

            this.subscribe("postRenderEvent", function() {
                search_placeholder_overlay.align();
            });
            this.search_placeholder_overlay = search_placeholder_overlay;
        });

        this.subscribe("postRenderEvent", function show_table() {

            // We can't do this until there is at least one record.
            if (!this.getRecord(0)) {
                return;
            }

            this.unsubscribe("postRenderEvent", show_table);

            var relative_widths = {};
            var column_count = cols.length;
            var we_have_useful_nvdata_widths = ("column_widths" in nvdata) && (cols.every(function(cd) {
                return cd.hidden || nvdata.column_widths[cd.key] || nvdata.column_widths[cd.key] === 0;
            }));
            if (we_have_useful_nvdata_widths) {
                for (var c = 0; c < column_count; c++) {
                    relative_widths[cols[c].key] = nvdata.column_widths[cols[c].key];
                }
            } else {
                relative_widths = this.size_columns();
            }

            // This overrides whatever nvdata has for the actions column.
            var actions_col = this.getColumn("actions");
            if (actions_col) {
                var first_actions_liner = this.getTdLinerEl({
                    record: this.getRecord(0),
                    column: this.getColumn("actions")
                });
                if (first_actions_liner) {
                    var first_link = first_actions_liner.children[0];
                    if (first_link) {
                        var last_link = DOM.getLastChild(first_actions_liner);
                        var left = DOM.getX(first_link);
                        var right = DOM.getX(last_link) + last_link.offsetWidth;
                        relative_widths.actions = {
                            value: right - left + 1,
                            absolute: true
                        };
                        this.getColumn("actions").fixed_width = true;
                    }
                }
            }

            this.set_width(this._initial_width, relative_widths);
            if (!we_have_useful_nvdata_widths) {
                this._save_column_widths();
            }

            var table = this;
            paginator.subscribe("rowsPerPageChange", function(args) {
                paginator.updateVisibility();
                table.get("nvdata").rows_per_page = paginator.all_records_shown ? 0 : args.newValue;
                table._save_nvdata();
            });

            DOM.setStyle(id + "_container", "visibility", "");
        });

        // for old IE (7, 6?)
        this.getTableEl().cellSpacing = 0;

        // tooltips
        this.subscribe("cellFormatEvent", function(oArgs) {
            if (!oArgs.el.title && !DOM.hasClass(oArgs.el.parentNode, "yui-dt-col-actions")) {
                oArgs.el.title = CPANEL.util.get_text_content(oArgs.el);
            }
        });


        this._column_select_link = DOM.get(id + "_column_select_link");
        if (this._column_select_link) {
            EVENT.on(this._column_select_link, "click", this.toggle_column_select, this, true);
        }

        var reload_link = DOM.get(id + "_reload_link");
        if (reload_link) {
            this._reload_link = reload_link;
            EVENT.on(reload_link, "click", this.reload, this, true);
        }

        this.subscribe("dataReturnEvent", function(args) {

        });
    };
    _Standard_Table.COLUMN_SELECT_ITEM_TEMPLATE = "<label><input type=\"checkbox\" {checked_html} /> {column_name_html}</label>";
    YAHOO.lang.extend(_Standard_Table, _SearchableDataTable, {

        initAttributes: function() {
            var table = this;

            this.setAttributeConfig("nvdata", {
                value: {},
                validator: YAHOO.lang.isObject
            });

            return _Standard_Table.superclass.initAttributes.apply(this, arguments);
        },

        reload: function() {
            if (this._reload_link) {
                DOM.addClass(this._reload_link, "reloading");
            }
            if (this.get("dynamicData")) {
                this.do_text_search();
                if (this._reload_link) {
                    this.subscribe("postRenderEvent", function stop_reloading() {
                        this.unsubscribe("postRenderEvent", stop_reloading);
                        DOM.removeClass(this._reload_link, "reloading");
                    });
                }
            } else {
                location.reload();
            }
        },

        toggle_column_select: function(e) {
            if (this._column_select_shown) {
                this._column_select_shown.destroy();
                EVENT.removeListener(document.body, "mousedown", this._column_select_shown.body_listener);
                delete this._column_select_shown;
                return;
            }

            var ctrl_el = this._column_select_link || DOM.get(this.getId() + "_column_select_link");
            if (ctrl_el) {
                var column_select = new YAHOO.widget.Overlay(this.getId() + "_column_select", {
                    context: [ctrl_el, "tr", "br"]
                });
                DOM.addClass(column_select.element, "cjt_table_column_select");

                var row_template = _Standard_Table.COLUMN_SELECT_ITEM_TEMPLATE;
                var body_html = "<ul class=\"cjt_table_column_select_list\">" + this.getColumnSet().flat.map(function(c) {
                    return "<li>" + YAHOO.lang.substitute(row_template, {
                        checked_html: (c.hidden ? "" : "checked='checked'"),
                        column_name_html: c.label.html_encode()
                    }) + "</li>";
                }).join("") + "</ul>";

                DOM.addClass(column_select.element, "column_select");

                column_select.showEvent.unsubscribe(column_select.showMacGeckoScrollbars, column_select);

                // blackhole this since there is no way to disable it
                column_select.showMacGeckoScrollbars = function() {};

                column_select.hideMacGeckoScrollbars();

                column_select.setBody(body_html);
                var inputs = DOM.getElementsBy(Boolean, "input", column_select.body);
                var table = this;
                inputs.forEach(function(el, idx) {
                    var key = table.getColumn(idx);
                    EVENT.addListener(el, "click", function(e) {
                        table[el.checked ? "showColumn" : "hideColumn"](key);
                    });
                });

                column_select.render(ctrl_el.parentNode);
                ctrl_el.parentNode.insertBefore(column_select.element, ctrl_el.nextSibling);

                column_select.show();

                column_select.hideEvent.subscribe(function() {

                    // for some reason this is necessary...
                    setTimeout(function() {
                        column_select.destroy();
                    }, 100);
                });

                YAHOO.util.Event.on(column_select.element, "mousedown", function(e) {
                    YAHOO.util.Event.stopPropagation(e);
                });
                var body_listener = function(e) {
                    var target = YAHOO.util.Event.getTarget(e);
                    if ((ctrl_el === target) || DOM.isAncestor(ctrl_el, target)) {
                        return;
                    }
                    EVENT.removeListener(document.body, "mousedown", body_listener);
                    table.toggle_column_select();
                };
                EVENT.on(document.body, "mousedown", body_listener);

                this._column_select_shown = column_select;
                column_select.body_listener = body_listener;
            }
        },


        _update_nvdata_hidden_columns: function() {
            var hidden_columns = {};
            this.getColumnSet().flat.forEach(function(c) {
                hidden_columns[c.key] = c.hidden;
            });
            this.get("nvdata").hidden_columns = hidden_columns;
        },
        _save_hidden_columns: function() {
            this._save_nvdata();
        },
        _save_column_widths: function() {
            var column_widths = {};
            var columns = this.getColumnSet().flat;
            for (var c = 0; c < columns.length; c++) {
                var cur_column = columns[c];
                if (!cur_column.hidden && cur_column.width) {
                    column_widths[cur_column.key] = cur_column.width;
                }
            }
            this.get("nvdata").column_widths = column_widths;
            this._save_nvdata();
        },

        _save_nvdata: function() {
            CPANEL.nvdata.save(this.get("nvdata"));
        }
    });

    if (!CPANEL.datatable) {
        CPANEL.datatable = {};
    }
    YAHOO.lang.augmentObject(CPANEL.datatable, {
        Standard_Table: _Standard_Table,
        SearchableDataTable: _SearchableDataTable,
        make_generateRequest_func: _make_generateRequest_func
    });

})();
