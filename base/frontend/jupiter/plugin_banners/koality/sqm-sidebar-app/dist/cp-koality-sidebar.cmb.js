(function (factory) {
    typeof define === 'function' && define.amd ? define(factory) :
    factory();
})((function () { 'use strict';

    var html = "<div id=\"container\">\n    <div id=\"main\">\n        <span id=\"description\">\n            <strong id=\"title\"></strong> - <span id=\"body\"></span>\n        </span>\n        <i id=\"close\"></i>\n    </div>\n    <button id=\"button-cta\">\n    </button>\n</div>\n";

    var cssReset = "*::before,\n*::after {\n    box-sizing: border-box;\n}\n\n* {\n    margin: 0;\n    padding: 0;\n}\n\na:not([class]) {\n    text-decoration-skip-ink: auto;\n}\n\nimg,\npicture,\nsvg,\nvideo,\ncanvas {\n    max-width: 100%;\n    height: auto;\n    vertical-align: middle;\n    font-style: italic;\n    background-repeat: no-repeat;\n    background-size: cover;\n}\n\ninput,\nbutton,\ntextarea,\nselect {\n    font: inherit;\n}\n\nhtml {\n    font-size: 16px;\n    /* base so that I can scale with rem units */\n}\n";

    var css = ":host {\n    font-family: \"Open Sans\", system-ui, -apple-system, \"Segoe UI\", sans-serif;\n}\n\ntd {\n    padding: .313rem;\n    margin: .313rem;\n}\n\ni {\n    font-style: normal;\n}\n\nbutton {\n    display: inline-flex;\n    justify-content: center;\n    align-items: center;\n    outline: none;\n    width: 100%;\n    cursor: pointer;\n    padding: 0.25rem 0.5rem;\n    border-radius: 0.2rem;\n    border: 0.0625rem solid #003da6;\n    background: #003da6;\n    color: white;\n}\n\n.loading-animation {\n    display: inline-block;\n    border: .1875rem solid white;\n    border-top: .1875rem solid #003DA6;\n    border-radius: 50%;\n    width: .625rem;\n    height: .625rem;\n    animation: spin 2s linear infinite;\n    margin-right: .625rem;\n}\n\n#description {\n    line-height: 150%;\n}\n\n#container {\n    display: flex;\n    padding: .625rem;\n    flex-direction: column;\n    align-items: flex-start;\n    gap: .625rem;\n    border-radius: .25rem;\n    border: 1px solid #003da6;\n    box-shadow: 0px 8px 20px 0px rgba(2, 2, 2, 0.04);\n}\n\n#main {\n    display: flex;\n    align-items: flex-start;\n    column-gap: .625rem;\n}\n\n#close {\n    font-weight: bold;\n    cursor: pointer;\n    display: inline-grid;\n    place-content: center;\n    aspect-ratio: 1;\n    border: solid black 2px;\n    border-radius: 50%;\n    height: 1rem;\n}\n\n#close::before {\n    content: \"\\00d7\";\n    color: black;\n    font-size: 1.125rem;\n}\n\n@keyframes spin {\n    0% {\n        transform: rotate(0deg);\n    }\n\n    100% {\n        transform: rotate(360deg);\n    }\n}\n";

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * Common http verbs
     */
    var HttpVerb;
    (function (HttpVerb) {
        /**
         * Get request
         */
        HttpVerb[HttpVerb["GET"] = 0] = "GET";
        /**
         * Head request
         */
        HttpVerb[HttpVerb["HEAD"] = 1] = "HEAD";
        /**
         * Post request
         */
        HttpVerb[HttpVerb["POST"] = 2] = "POST";
        /**
         * Put request
         */
        HttpVerb[HttpVerb["PUT"] = 3] = "PUT";
        /**
         * Delete request
         */
        HttpVerb[HttpVerb["DELETE"] = 4] = "DELETE";
        /**
         * Connect request
         */
        HttpVerb[HttpVerb["CONNECT"] = 5] = "CONNECT";
        /**
         * Options request
         */
        HttpVerb[HttpVerb["OPTIONS"] = 6] = "OPTIONS";
        /**
         * Trace request
         */
        HttpVerb[HttpVerb["TRACE"] = 7] = "TRACE";
        /**
         * Patch request
         */
        HttpVerb[HttpVerb["PATCH"] = 8] = "PATCH";
    })(HttpVerb || (HttpVerb = {}));

    // MIT License
    /**
     * Default argument serialization rules for each well known HTTP verb.
     */
    class DefaultArgumentSerializationRules {
        /**
         * Construct the lookup table for well know verbs.
         */
        constructor() {
            this.map = {};
            // fallback rule if the verb is not defined.
            this.map["DEFAULT"] = {
                verb: "DEFAULT",
                dataInBody: true,
            };
            [HttpVerb.GET, HttpVerb.DELETE, HttpVerb.HEAD].forEach((verb) => {
                const label = HttpVerb[verb].toString();
                this.map[label] = {
                    verb: label,
                    dataInBody: false,
                };
            });
            [HttpVerb.POST, HttpVerb.PUT, HttpVerb.PATCH].forEach((verb) => {
                const label = HttpVerb[verb].toString();
                this.map[label] = {
                    verb: label,
                    dataInBody: true,
                };
            });
        }
        /**
         * Get a rule for serialization of arguments. This tells the generators where
         * argument data is packaged in a request. Arguments can be located in one of
         * the following:
         *
         *   Body,
         *   Url
         *
         * @param verb verb to lookup.
         */
        getRule(verb) {
            const name = typeof verb === "string" ? verb : HttpVerb[verb].toString();
            let rule = this.map[name];
            if (!rule) {
                rule = this.map["DEFAULT"];
            }
            return rule;
        }
    }
    /**
     * Singleton with the default argument serialization rules in it.
     */
    const argumentSerializationRules = new DefaultArgumentSerializationRules();

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * Convert from a JavaScript boolean to a Perl boolean.
     */
    function fromBoolean(value) {
        return value ? "1" : "0";
    }

    // MIT License
    /**
     * An name/value pair argument
     */
    class Argument {
        /**
         * Build a new Argument.
         *
         * @param name Name of the argument
         * @param value Value of the argument.
         */
        constructor(name, value) {
            if (!name) {
                throw new Error("You must provide a name when creating a name/value argument");
            }
            this.name = name;
            this.value = value;
        }
    }

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * The filter operator defines the rule used to compare data in a column with the passed-in value. It
     * behaves something like:
     *
     *   const value = 1;
     *   data.map(item => item[column])
     *       .filter(itemValue => operator(itemValue, value));
     *
     * where item is the data from the column
     */
    var FilterOperator;
    (function (FilterOperator) {
        /**
         * String contains value
         */
        FilterOperator[FilterOperator["Contains"] = 0] = "Contains";
        /**
         * String begins with value
         */
        FilterOperator[FilterOperator["Begins"] = 1] = "Begins";
        /**
         * String ends with value
         */
        FilterOperator[FilterOperator["Ends"] = 2] = "Ends";
        /**
         * String matches pattern in value
         */
        FilterOperator[FilterOperator["Matches"] = 3] = "Matches";
        /**
         * Column value equals value
         */
        FilterOperator[FilterOperator["Equal"] = 4] = "Equal";
        /**
         * Column value not equal value
         */
        FilterOperator[FilterOperator["NotEqual"] = 5] = "NotEqual";
        /**
         * Column value is less than value
         */
        FilterOperator[FilterOperator["LessThan"] = 6] = "LessThan";
        /**
         * Column value is less than value using unlimited rules.
         */
        FilterOperator[FilterOperator["LessThanUnlimited"] = 7] = "LessThanUnlimited";
        /**
         * Column value is greater than value.
         */
        FilterOperator[FilterOperator["GreaterThan"] = 8] = "GreaterThan";
        /**
         * Column value is greater than value using unlimited rules.
         */
        FilterOperator[FilterOperator["GreaterThanUnlimited"] = 9] = "GreaterThanUnlimited";
        /**
         * Column value is defined. Value is ignored in this case.
         */
        FilterOperator[FilterOperator["Defined"] = 10] = "Defined";
        /**
         * Column value is undefined. Value is ignored in this case.
         */
        FilterOperator[FilterOperator["Undefined"] = 11] = "Undefined";
    })(FilterOperator || (FilterOperator = {}));
    /**
     * Defines a filter request for a Api call.
     */
    class Filter {
        /**
         * Construct a new Filter object.
         *
         * @param column Column name requests. Must be non-empty and exist on the related backend collection.
         * @param operator Comparison operator to use when applying the filter.
         * @param value Value to compare the columns value too.
         */
        constructor(column, operator, value) {
            if (!column) {
                throw new Error("You must define a non-empty column name.");
            }
            this.column = column;
            this.operator = operator;
            this.value = value;
        }
    }

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    const DEFAULT_PAGE_SIZE = 20;
    /**
     * When passed in the pageSize, will request all available records in a single page. Note: The backend process may not honor this request.
     */
    const ALL = Number.POSITIVE_INFINITY;
    /**
     * Defines a pagination request for an API.
     */
    class Pager {
        /**
         * Create a new pagination object.
         *
         * @param page Page to request. From 1 .. n where n is the set.length % pageSize. Defaults to 1.
         * @param pageSize Number of records to request in a page of data. Defaults to DEFAULT_PAGE_SIZE.
         *                          If the string 'all' is passed, then all the records are requested. Note: The backend
         *                          system may still impose page size limits in this case.
         */
        constructor(page = 1, pageSize = DEFAULT_PAGE_SIZE) {
            if (page <= 0) {
                throw new Error("The page must be 1 or greater. This is the logical page, not a programming index.");
            }
            if (pageSize <= 0) {
                throw new Error("The pageSize must be set to 'ALL' or a number > 0");
            }
            this.page = page;
            this.pageSize = pageSize;
        }
        /**
         * Check if the pagesize is set to ALL.
         *
         * @return true if requesting all records, false otherwise.
         */
        all() {
            return this.pageSize === ALL;
        }
    }

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * Sorting direction. The SortType and SortDirection combine to define the sorting for collections returned.
     */
    var SortDirection;
    (function (SortDirection) {
        /**
         * Records are sorted from low value to high value based on the SortType
         */
        SortDirection[SortDirection["Ascending"] = 0] = "Ascending";
        /**
         * Records are sorted from high value to low value based on the SortType
         */
        SortDirection[SortDirection["Descending"] = 1] = "Descending";
    })(SortDirection || (SortDirection = {}));
    /**
     * Sorting type. Defines how values are compared.
     */
    var SortType;
    (function (SortType) {
        /**
         * Uses character-by-character comparison.
         */
        SortType[SortType["Lexicographic"] = 0] = "Lexicographic";
        /**
         * Special rule for handing IPv4 comparison. This takes into account the segments.
         */
        SortType[SortType["Ipv4"] = 1] = "Ipv4";
        /**
         * Assumes the values are numeric and compares them using number rules.
         */
        SortType[SortType["Numeric"] = 2] = "Numeric";
        /**
         * Special rule for certain data where 0 is considered unlimited.
         */
        SortType[SortType["NumericZeroAsMax"] = 3] = "NumericZeroAsMax";
    })(SortType || (SortType = {}));
    /**
     * Defines a sort rule. These can be combined into a list to define a complex sort for a list dataset.
     */
    class Sort {
        /**
         * Create a new instance of a Sort
         *
         * @param column Column to sort
         * @param direction Optional sort direction. Defaults to Ascending
         * @param type Optional sort type. Defaults to Lexicographic
         */
        constructor(column, direction = SortDirection.Ascending, type = SortType.Lexicographic) {
            if (!column) {
                throw new Error("You must provide a non-empty column name for a Sort rule.");
            }
            this.column = column;
            this.direction = direction;
            this.type = type;
        }
    }

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * HTTP Headers Collection Abstraction
     *
     * The abstraction is an adapter to allow easy transformation of the headers array
     * into various formats for external HTTP libraries.
     */
    class Headers {
        /**
         * Create the adapter.
         *
         * @param headers - List of headers.
         */
        constructor(headers = []) {
            this.headers = headers;
        }
        /**
         * Push a header into the collection.
         *
         * @param header - A header to add to the collection
         */
        push(header) {
            this.headers.push(header);
        }
        /**
         * Iterator for the headers collection.
         *
         * @param fn - Transform for the forEach
         * @param thisArg - Optional reference to `this` to apply to the transform function.
         */
        forEach(fn, thisArg) {
            this.headers.forEach(fn, thisArg);
        }
        /**
         * Retrieve the headers as an array of Headers
         */
        toArray() {
            const copy = [];
            this.headers.forEach((h) => copy.push({ name: h.name, value: h.value }));
            return copy;
        }
        /**
         * Retrieve the headers as an object
         */
        toObject() {
            return this.headers.reduce((o, header) => {
                o[header.name] = header.value;
                return o;
            }, {});
        }
    }
    class CustomHeader {
        constructor(_header) {
            this._header = _header;
        }
        get name() {
            return this._header.name;
        }
        get value() {
            return this._header.value;
        }
    }
    class WhmApiTokenInvalidError extends Error {
        constructor(m) {
            super(m);
            this.name = "WhmApiTokenInvalidError";
            // Set the prototype explicitly. This fixes unit tests.
            Object.setPrototypeOf(this, WhmApiTokenInvalidError.prototype);
        }
    }
    class WhmApiTokenMismatchError extends Error {
        constructor(m) {
            super(m);
            this.name = "WhmApiTokenMismatchError";
            // Set the prototype explicitly. This fixes unit tests.
            Object.setPrototypeOf(this, WhmApiTokenMismatchError.prototype);
        }
    }
    class WhmApiTokenHeader extends CustomHeader {
        constructor(token, user) {
            if (!token) {
                throw new WhmApiTokenInvalidError("You must pass a valid token to the constructor.");
            }
            if (!user && !/^.+:/.test(token)) {
                throw new WhmApiTokenInvalidError("You must pass a WHM username associated with the WHM API token.");
            }
            if (!user && !/:.+$/.test(token)) {
                throw new WhmApiTokenInvalidError("You must pass a valid WHM API token.");
            }
            super({
                name: "Authorization",
                value: `whm ${user ? user + ":" : ""}${token}`,
            });
        }
    }

    // MIT License
    /**
     * Abstract base class for all Request objects. Developers should
     * create a subclass of this that implements the generate() method.
     */
    class Request {
        /**
         * Create a new request.
         *
         * @param init   Optional request object used to initialize this object.
         */
        constructor(init) {
            /**
             * Namespace where the API call lives
             * @type {string}
             */
            this.namespace = "";
            /**
             * Method name of the API call.
             * @type {string}
             */
            this.method = "";
            /**
             * Optional list of arguments for the API call.
             * @type {IArgument[]}
             */
            this.arguments = [];
            /**
             * Optional list of sorting rules to pass to the API call.
             */
            this.sorts = [];
            /**
             * Optional list of filter rules to pass to the API call.
             */
            this.filters = [];
            /**
             * Optional list of columns to include with the response to the API call.
             */
            this.columns = [];
            /**
             * Optional pager rule to pass to the API.
             */
            this.pager = new Pager();
            /**
             * Optional custom headers collection
             */
            this.headers = new Headers();
            this._usePager = false;
            /**
             * Default configuration object.
             */
            this.defaultConfig = {
                analytics: false,
                json: false,
            };
            /**
             * Optional configuration information
             */
            this.config = this.defaultConfig;
            if (init) {
                this.method = init.method;
                if (init.namespace) {
                    this.namespace = init.namespace;
                }
                if (init.arguments) {
                    init.arguments.forEach((argument) => {
                        this.addArgument(argument);
                    });
                }
                if (init.sorts) {
                    init.sorts.forEach((sort) => {
                        this.addSort(sort);
                    });
                }
                if (init.filters) {
                    init.filters.forEach((filter) => {
                        this.addFilter(filter);
                    });
                }
                if (init.columns) {
                    init.columns.forEach((column) => this.addColumn(column));
                }
                if (init.pager) {
                    this.paginate(init.pager);
                }
                if (init.config) {
                    this.config = init.config;
                }
                else {
                    this.config = this.defaultConfig;
                }
                if (init.headers) {
                    init.headers.forEach((header) => {
                        this.addHeader(header);
                    });
                }
            }
        }
        /**
         * Use the pager only if true.
         */
        get usePager() {
            return this._usePager;
        }
        /**
         * Add an argument to the request.
         *
         * @param argument
         * @return Updated Request object.
         */
        addArgument(argument) {
            if (argument instanceof Argument) {
                this.arguments.push(argument);
            }
            else {
                this.arguments.push(new Argument(argument.name, argument.value));
            }
            return this;
        }
        /**
         * Add sorting rule to the request.
         *
         * @param sort Sort object with sorting information.
         * @return Updated Request object.
         */
        addSort(sort) {
            if (sort instanceof Sort) {
                this.sorts.push(sort);
            }
            else {
                this.sorts.push(new Sort(sort.column, sort.direction, sort.type));
            }
            return this;
        }
        /**
         * Add a filter to the request.
         *
         * @param filter Filter object with filter information.
         * @return Updated Request object.
         */
        addFilter(filter) {
            if (filter instanceof Filter) {
                this.filters.push(filter);
            }
            else {
                this.filters.push(new Filter(filter.column, filter.operator, filter.value));
            }
            return this;
        }
        /**
         * Add a column to include in the request. If no columns are specified, all columns are retrieved.
         *
         * @param name Name of a column
         * @return Updated Request object.
         */
        addColumn(column) {
            this.columns.push(column);
            return this;
        }
        /**
         * Add a custom http header to the request
         *
         * @param name Name of a column
         * @return Updated Request object.
         */
        addHeader(header) {
            if (header instanceof CustomHeader) {
                this.headers.push(header);
            }
            else {
                this.headers.push(new CustomHeader(header));
            }
            return this;
        }
        /**
         * Set the pager setting for the request.
         *
         * @param pager Pager object with pagination information.
         * @return Updated Request object.
         */
        paginate(pager) {
            if (pager instanceof Pager) {
                this.pager = pager;
            }
            else {
                this.pager = new Pager(pager.page, pager.pageSize || 20);
            }
            this._usePager = true;
            return this;
        }
    }

    var commonjsGlobal = typeof globalThis !== 'undefined' ? globalThis : typeof window !== 'undefined' ? window : typeof global !== 'undefined' ? global : typeof self !== 'undefined' ? self : {};

    function getDefaultExportFromCjs (x) {
    	return x && x.__esModule && Object.prototype.hasOwnProperty.call(x, 'default') ? x['default'] : x;
    }

    /**
     * Checks if `value` is `undefined`.
     *
     * @static
     * @since 0.1.0
     * @memberOf _
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is `undefined`, else `false`.
     * @example
     *
     * _.isUndefined(void 0);
     * // => true
     *
     * _.isUndefined(null);
     * // => false
     */

    function isUndefined(value) {
      return value === undefined;
    }

    var isUndefined_1 = isUndefined;

    var isUndefined$1 = /*@__PURE__*/getDefaultExportFromCjs(isUndefined_1);

    /**
     * Checks if `value` is `null`.
     *
     * @static
     * @memberOf _
     * @since 0.1.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is `null`, else `false`.
     * @example
     *
     * _.isNull(null);
     * // => true
     *
     * _.isNull(void 0);
     * // => false
     */

    function isNull(value) {
      return value === null;
    }

    var isNull_1 = isNull;

    var isNull$1 = /*@__PURE__*/getDefaultExportFromCjs(isNull_1);

    // MIT License
    /**
     * Types of message that can be in a response.
     */
    var MessageType;
    (function (MessageType) {
        /**
         * Message is an error.
         */
        MessageType[MessageType["Error"] = 0] = "Error";
        /**
         * Message is a warning.
         */
        MessageType[MessageType["Warning"] = 1] = "Warning";
        /**
         * Message is informational.
         */
        MessageType[MessageType["Information"] = 2] = "Information";
        /**
         * The message type is unknown.
         */
        MessageType[MessageType["Unknown"] = 3] = "Unknown";
    })(MessageType || (MessageType = {}));
    const DefaultMetaData = {
        isPaged: false,
        isFiltered: false,
        record: 0,
        page: 0,
        pageSize: 0,
        totalRecords: 0,
        totalPages: 0,
        recordsBeforeFilter: 0,
        batch: false,
        properties: {},
    };
    /**
     * Deep cloning of a object to avoid reference overwritting.
     *
     * @param data Metadata object to be cloned.
     * @returns Cloned Metadata object.
     */
    function clone(data) {
        return JSON.parse(JSON.stringify(data));
    }
    /**
     * Base class for all response. Must be sub-classed by a real implementation.
     */
    class Response {
        /**
         * Build a new response object from the response. Note, this class should not be called
         * directly.
         * @param response Complete data passed from the server. Probably it's been parsed using JSON.parse().
         * @param options for how to handle the processing of the response data.
         */
        constructor(response, options) {
            /**
             * The status code returned by the API. Usually 1 for success, 0 for failure.
             */
            this.status = 0;
            /**
             * List of messages related to the response.
             */
            this.messages = [];
            /**
             * Additional data returned about the request. Paging, filtering, and maybe other custom properties.
             */
            this.meta = clone(DefaultMetaData);
            /**
             * Options about how to handle the response processing.
             */
            this.options = {
                keepUnprocessedResponse: false,
            };
            if (isUndefined$1(response) || isNull$1(response)) {
                throw new Error("The response was unexpectedly undefined or null");
            }
            if (options) {
                this.options = options;
            }
            if (this.options.keepUnprocessedResponse) {
                this.raw = JSON.parse(JSON.stringify(response)); // deep clone
            }
        }
        /**
         * Checks if the API was successful.
         *
         * @return true if successful, false if failure.
         */
        get success() {
            return this.status > 0;
        }
        /**
         * Checks if the api failed.
         *
         * @return true if the API reports failure, false otherwise.
         */
        get failed() {
            return this.status === 0;
        }
        /**
         * Get the list of messages based on the requested type.
         *
         * @param type Type of the message to look up.
         * @return List of messages that match the filter.
         */
        _getMessages(type) {
            return this.messages.filter((message) => message.type === type);
        }
        /**
         * Get the list of error messages.
         *
         * @return List of errors.
         */
        get errors() {
            return this._getMessages(MessageType.Error);
        }
        /**
         * Get the list of warning messages.
         *
         * @return List of warnings.
         */
        get warnings() {
            return this._getMessages(MessageType.Warning);
        }
        /**
         * Get the list of informational messages.
         *
         * @return List of informational messages.
         */
        get infoMessages() {
            return this._getMessages(MessageType.Information);
        }
        /**
         * Checks if there are any messages of a given type.
         * @param type Type of the message to check for.
         * @return true if there are messages of the requested type. false otherwise.
         */
        _hasMessages(type) {
            return (this.messages.filter((message) => message.type === type).length > 0);
        }
        /**
         * Checks if there are any error messages in the response.
         *
         * @return true if there are error messages, false otherwise.
         */
        get hasErrors() {
            return this._hasMessages(MessageType.Error);
        }
        /**
         * Checks if there are any warnings in the response.
         *
         * @return true if there are warnings, false otherwise.
         */
        get hasWarnings() {
            return this._hasMessages(MessageType.Warning);
        }
        /**
         * Checks if there are any informational messages in the response.
         *
         * @return true if there are informational messages, false otherwise.
         */
        get hasInfoMessages() {
            return this._hasMessages(MessageType.Information);
        }
        /**
         * Check if the response was paginated by the backend.
         *
         * @return true if the backend returned a page of the total records.
         */
        get isPaged() {
            return this.meta.isPaged;
        }
        /**
         * Check if the response was filtered by the backend.
         *
         * @return true if the backend filtered the records.
         */
        get isFiltered() {
            return this.meta.isFiltered;
        }
    }

    /** Detect free variable `global` from Node.js. */

    var freeGlobal$1 = typeof commonjsGlobal == 'object' && commonjsGlobal && commonjsGlobal.Object === Object && commonjsGlobal;

    var _freeGlobal = freeGlobal$1;

    var freeGlobal = _freeGlobal;

    /** Detect free variable `self`. */
    var freeSelf = typeof self == 'object' && self && self.Object === Object && self;

    /** Used as a reference to the global object. */
    var root$1 = freeGlobal || freeSelf || Function('return this')();

    var _root = root$1;

    var root = _root;

    /** Built-in value references. */
    var Symbol$3 = root.Symbol;

    var _Symbol = Symbol$3;

    var Symbol$2 = _Symbol;

    /** Used for built-in method references. */
    var objectProto$2 = Object.prototype;

    /** Used to check objects for own properties. */
    var hasOwnProperty$1 = objectProto$2.hasOwnProperty;

    /**
     * Used to resolve the
     * [`toStringTag`](http://ecma-international.org/ecma-262/7.0/#sec-object.prototype.tostring)
     * of values.
     */
    var nativeObjectToString$1 = objectProto$2.toString;

    /** Built-in value references. */
    var symToStringTag$1 = Symbol$2 ? Symbol$2.toStringTag : undefined;

    /**
     * A specialized version of `baseGetTag` which ignores `Symbol.toStringTag` values.
     *
     * @private
     * @param {*} value The value to query.
     * @returns {string} Returns the raw `toStringTag`.
     */
    function getRawTag$1(value) {
      var isOwn = hasOwnProperty$1.call(value, symToStringTag$1),
          tag = value[symToStringTag$1];

      try {
        value[symToStringTag$1] = undefined;
        var unmasked = true;
      } catch (e) {}

      var result = nativeObjectToString$1.call(value);
      if (unmasked) {
        if (isOwn) {
          value[symToStringTag$1] = tag;
        } else {
          delete value[symToStringTag$1];
        }
      }
      return result;
    }

    var _getRawTag = getRawTag$1;

    /** Used for built-in method references. */

    var objectProto$1 = Object.prototype;

    /**
     * Used to resolve the
     * [`toStringTag`](http://ecma-international.org/ecma-262/7.0/#sec-object.prototype.tostring)
     * of values.
     */
    var nativeObjectToString = objectProto$1.toString;

    /**
     * Converts `value` to a string using `Object.prototype.toString`.
     *
     * @private
     * @param {*} value The value to convert.
     * @returns {string} Returns the converted string.
     */
    function objectToString$1(value) {
      return nativeObjectToString.call(value);
    }

    var _objectToString = objectToString$1;

    var Symbol$1 = _Symbol,
        getRawTag = _getRawTag,
        objectToString = _objectToString;

    /** `Object#toString` result references. */
    var nullTag = '[object Null]',
        undefinedTag = '[object Undefined]';

    /** Built-in value references. */
    var symToStringTag = Symbol$1 ? Symbol$1.toStringTag : undefined;

    /**
     * The base implementation of `getTag` without fallbacks for buggy environments.
     *
     * @private
     * @param {*} value The value to query.
     * @returns {string} Returns the `toStringTag`.
     */
    function baseGetTag$5(value) {
      if (value == null) {
        return value === undefined ? undefinedTag : nullTag;
      }
      return (symToStringTag && symToStringTag in Object(value))
        ? getRawTag(value)
        : objectToString(value);
    }

    var _baseGetTag = baseGetTag$5;

    /**
     * Checks if `value` is object-like. A value is object-like if it's not `null`
     * and has a `typeof` result of "object".
     *
     * @static
     * @memberOf _
     * @since 4.0.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is object-like, else `false`.
     * @example
     *
     * _.isObjectLike({});
     * // => true
     *
     * _.isObjectLike([1, 2, 3]);
     * // => true
     *
     * _.isObjectLike(_.noop);
     * // => false
     *
     * _.isObjectLike(null);
     * // => false
     */

    function isObjectLike$5(value) {
      return value != null && typeof value == 'object';
    }

    var isObjectLike_1 = isObjectLike$5;

    var baseGetTag$4 = _baseGetTag,
        isObjectLike$4 = isObjectLike_1;

    /** `Object#toString` result references. */
    var boolTag = '[object Boolean]';

    /**
     * Checks if `value` is classified as a boolean primitive or object.
     *
     * @static
     * @memberOf _
     * @since 0.1.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is a boolean, else `false`.
     * @example
     *
     * _.isBoolean(false);
     * // => true
     *
     * _.isBoolean(null);
     * // => false
     */
    function isBoolean(value) {
      return value === true || value === false ||
        (isObjectLike$4(value) && baseGetTag$4(value) == boolTag);
    }

    var isBoolean_1 = isBoolean;

    var isBoolean$1 = /*@__PURE__*/getDefaultExportFromCjs(isBoolean_1);

    var baseGetTag$3 = _baseGetTag,
        isObjectLike$3 = isObjectLike_1;

    /** `Object#toString` result references. */
    var numberTag = '[object Number]';

    /**
     * Checks if `value` is classified as a `Number` primitive or object.
     *
     * **Note:** To exclude `Infinity`, `-Infinity`, and `NaN`, which are
     * classified as numbers, use the `_.isFinite` method.
     *
     * @static
     * @memberOf _
     * @since 0.1.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is a number, else `false`.
     * @example
     *
     * _.isNumber(3);
     * // => true
     *
     * _.isNumber(Number.MIN_VALUE);
     * // => true
     *
     * _.isNumber(Infinity);
     * // => true
     *
     * _.isNumber('3');
     * // => false
     */
    function isNumber(value) {
      return typeof value == 'number' ||
        (isObjectLike$3(value) && baseGetTag$3(value) == numberTag);
    }

    var isNumber_1 = isNumber;

    var isNumber$1 = /*@__PURE__*/getDefaultExportFromCjs(isNumber_1);

    /**
     * Checks if `value` is classified as an `Array` object.
     *
     * @static
     * @memberOf _
     * @since 0.1.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is an array, else `false`.
     * @example
     *
     * _.isArray([1, 2, 3]);
     * // => true
     *
     * _.isArray(document.body.children);
     * // => false
     *
     * _.isArray('abc');
     * // => false
     *
     * _.isArray(_.noop);
     * // => false
     */

    var isArray$2 = Array.isArray;

    var isArray_1 = isArray$2;

    var isArray$3 = /*@__PURE__*/getDefaultExportFromCjs(isArray_1);

    var baseGetTag$2 = _baseGetTag,
        isArray$1 = isArray_1,
        isObjectLike$2 = isObjectLike_1;

    /** `Object#toString` result references. */
    var stringTag = '[object String]';

    /**
     * Checks if `value` is classified as a `String` primitive or object.
     *
     * @static
     * @since 0.1.0
     * @memberOf _
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is a string, else `false`.
     * @example
     *
     * _.isString('abc');
     * // => true
     *
     * _.isString(1);
     * // => false
     */
    function isString(value) {
      return typeof value == 'string' ||
        (!isArray$1(value) && isObjectLike$2(value) && baseGetTag$2(value) == stringTag);
    }

    var isString_1 = isString;

    var isString$1 = /*@__PURE__*/getDefaultExportFromCjs(isString_1);

    /**
     * Creates a unary function that invokes `func` with its argument transformed.
     *
     * @private
     * @param {Function} func The function to wrap.
     * @param {Function} transform The argument transform.
     * @returns {Function} Returns the new function.
     */

    function overArg$1(func, transform) {
      return function(arg) {
        return func(transform(arg));
      };
    }

    var _overArg = overArg$1;

    var overArg = _overArg;

    /** Built-in value references. */
    var getPrototype$1 = overArg(Object.getPrototypeOf, Object);

    var _getPrototype = getPrototype$1;

    var baseGetTag$1 = _baseGetTag,
        getPrototype = _getPrototype,
        isObjectLike$1 = isObjectLike_1;

    /** `Object#toString` result references. */
    var objectTag = '[object Object]';

    /** Used for built-in method references. */
    var funcProto = Function.prototype,
        objectProto = Object.prototype;

    /** Used to resolve the decompiled source of functions. */
    var funcToString = funcProto.toString;

    /** Used to check objects for own properties. */
    var hasOwnProperty = objectProto.hasOwnProperty;

    /** Used to infer the `Object` constructor. */
    var objectCtorString = funcToString.call(Object);

    /**
     * Checks if `value` is a plain object, that is, an object created by the
     * `Object` constructor or one with a `[[Prototype]]` of `null`.
     *
     * @static
     * @memberOf _
     * @since 0.8.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is a plain object, else `false`.
     * @example
     *
     * function Foo() {
     *   this.a = 1;
     * }
     *
     * _.isPlainObject(new Foo);
     * // => false
     *
     * _.isPlainObject([1, 2, 3]);
     * // => false
     *
     * _.isPlainObject({ 'x': 0, 'y': 0 });
     * // => true
     *
     * _.isPlainObject(Object.create(null));
     * // => true
     */
    function isPlainObject(value) {
      if (!isObjectLike$1(value) || baseGetTag$1(value) != objectTag) {
        return false;
      }
      var proto = getPrototype(value);
      if (proto === null) {
        return true;
      }
      var Ctor = hasOwnProperty.call(proto, 'constructor') && proto.constructor;
      return typeof Ctor == 'function' && Ctor instanceof Ctor &&
        funcToString.call(Ctor) == objectCtorString;
    }

    var isPlainObject_1 = isPlainObject;

    var isPlainObject$1 = /*@__PURE__*/getDefaultExportFromCjs(isPlainObject_1);

    // MIT License
    /**
     * Verify if the value can be serialized to JSON
     *
     * @param value Value to check.
     * @source https://stackoverflow.com/questions/30579940/reliable-way-to-check-if-objects-is-serializable-in-javascript#answer-30712764
     */
    function isSerializable(value) {
        if (isUndefined$1(value) ||
            isNull$1(value) ||
            isBoolean$1(value) ||
            isNumber$1(value) ||
            isString$1(value)) {
            return true;
        }
        if (!isPlainObject$1(value) && !isArray$3(value)) {
            return false;
        }
        for (const key in value) {
            if (!isSerializable(value[key])) {
                return false;
            }
        }
        return true;
    }

    // MIT License
    /**
     * Encode parameters using application/x-www-form-urlencoded
     */
    class WwwFormUrlArgumentEncoder {
        constructor() {
            this.contentType = "application/x-www-form-urlencoded";
            this.separatorStart = "";
            this.separatorEnd = "";
            this.recordSeparator = "&";
        }
        /**
         * Encode a given value into the application/x-www-form-urlencoded.
         *
         * @param name Name of the field, may be empty string.
         * @param value Value to serialize
         * @param last True if this is the last argument being serialized.
         * @return Encoded version of the argument.
         */
        encode(name, value, last) {
            if (!name) {
                throw new Error("Name must have a non-empty value");
            }
            return (`${name}=${encodeURIComponent(value.toString())}` +
                (!last ? this.recordSeparator : ""));
        }
    }
    /**
     * Encode the parameter into JSON
     */
    class JsonArgumentEncoder {
        constructor() {
            this.contentType = "application/json";
            this.separatorStart = "{";
            this.separatorEnd = "}";
            this.recordSeparator = ",";
        }
        /**
         * Encode a given value into the JSON application/json body.
         *
         * @param name Name of the field.
         * @param value Value to serialize
         * @param last True if this is the last argument being serialized.
         * @return {string}        Encoded version of the argument.
         */
        encode(name, value, last) {
            if (!name) {
                throw new Error("Name must have a non-empty value");
            }
            if (!isSerializable(value)) {
                throw new Error("The passed in value can not be serialized to JSON");
            }
            return (JSON.stringify(name) +
                ":" +
                JSON.stringify(value) +
                (!last ? this.recordSeparator : ""));
        }
    }

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * Check if the protocol is https.
     * @param  protocol Protocol to test
     * @return true if its https: in any case, false otherwise.
     */
    function isHttps(protocol) {
        return /^https:$/i.test(protocol);
    }
    /**
     * Check if the protocol is http.
     * @param  protocol Protocol to test
     * @return true if its http: in any case, false otherwise.
     */
    function isHttp(protocol) {
        return /^http:$/i.test(protocol);
    }
    /**
     * Strip any trailing slashes from a string.
     *
     * @method stripTrailingSlash
     * @param  path The path string to process.
     * @return The path string without a trailing slash.
     */
    function stripTrailingSlash(path) {
        return path && path.replace(/\/?$/, "");
    }
    // This will work in any context except a proxy URL to cPanel or Webmail
    // that accesses a URL outside /frontend (cPanel) or /webmail (Webmail),
    // but URLs like that are non-production by definition.
    const PortToApplicationMap = {
        "80": "other",
        "443": "other",
        "2082": "cpanel",
        "2083": "cpanel",
        "2086": "whostmgr",
        "2087": "whostmgr",
        "2095": "webmail",
        "2096": "webmail",
        "9876": "unittest",
        "9877": "unittest",
        "9878": "unittest",
        "9879": "unittest",
        frontend: "cpanel",
        webmail: "webmail",
    };
    /**
     * Helper class used to calculate paths within cPanel applications.
     */
    class ApplicationPath {
        /**
         * Create the PathHelper. This class is used to help generate paths
         * within an application. It has special knowledge about how paths are
         * constructed in the cPanel family of applications.
         *
         * @param location Abstraction for the window.location object to aid in unit testing this module.
         */
        constructor(location) {
            this.unprotectedPaths = ["/resetpass", "/invitation"];
            this.protocol = location.protocol;
            let port = location.port;
            if (!port) {
                // Since some browsers won't fill this in, we have to derive it from
                // the protocol if it's not provided in the window.location object.
                if (isHttps(this.protocol)) {
                    port = "443";
                }
                else if (isHttp(this.protocol)) {
                    port = "80";
                }
            }
            this.domain = location.hostname;
            this.port = parseInt(port, 10);
            this.path = location.pathname;
            const pathMatch = 
            // eslint-disable-next-line no-useless-escape -- regex, not a string
            this.path.match(/((?:\/cpsess\d+)?)(?:\/([^\/]+))?/) || [];
            // For proxy subdomains, we look at the first subdomain to identify the application.
            if (/^whm\./.test(this.domain)) {
                this.applicationName = PortToApplicationMap["2087"];
            }
            else if (/^cpanel\./.test(this.domain)) {
                this.applicationName = PortToApplicationMap["2083"];
            }
            else if (/^webmail\./.test(this.domain)) {
                this.applicationName = PortToApplicationMap["2095"];
            }
            else {
                this.applicationName =
                    PortToApplicationMap[port.toString()] ||
                        PortToApplicationMap[pathMatch[2]] ||
                        "whostmgr";
            }
            this.securityToken = pathMatch[1] || "";
            this.applicationPath = this.securityToken
                ? this.path.replace(this.securityToken, "")
                : this.path;
            this.theme = "";
            if (!this.isUnprotected && (this.isCpanel || this.isWebmail)) {
                const folders = this.path.split("/");
                this.theme = folders[3];
            }
            this.themePath = "";
            let themePath = this.securityToken + "/";
            if (this.isUnprotected) {
                themePath = "/";
            }
            else if (this.isCpanel) {
                themePath += "frontend/" + this.theme + "/";
            }
            else if (this.isWebmail) {
                themePath += "webmail/" + this.theme + "/";
            }
            else if (this.isOther) {
                // For unrecognized applications, use the path passed in PAGE.THEME_PATH
                themePath = "/";
            }
            this.themePath = themePath;
            this.rootUrl = this.protocol + "//" + this.domain + ":" + this.port;
        }
        /**
         * Return whether we are running inside some other framework or application
         *
         * @return true if this is an unrecognized application or framework; false otherwise
         */
        get isOther() {
            return /other/i.test(this.applicationName);
        }
        /**
         * Return whether we are running inside an unprotected path
         *
         * @return true if this is unprotected; false otherwise
         */
        get isUnprotected() {
            return (!this.securityToken &&
                this.unprotectedPaths.indexOf(stripTrailingSlash(this.applicationPath)) !== -1);
        }
        /**
         * Return whether we are running inside cPanel or something else (e.g., WHM)
         *
         * @return true if this is cPanel; false otherwise
         */
        get isCpanel() {
            return /cpanel/i.test(this.applicationName);
        }
        /**
         * Return whether we are running inside WHM or something else (e.g., WHM)
         *
         * @return true if this is WHM; false otherwise
         */
        get isWhm() {
            return /whostmgr/i.test(this.applicationName);
        }
        /**
         * Return whether we are running inside WHM or something else (e.g., WHM)
         *
         * @return true if this is Webmail; false otherwise
         */
        get isWebmail() {
            return /webmail/i.test(this.applicationName);
        }
        /**
         * Get the domain relative path for the relative URL path.
         *
         * @param relative Relative path to the resource.
         * @return Domain relative URL path including theme, if applicable, for the application to the file.
         */
        buildPath(relative) {
            return this.themePath + relative;
        }
        /**
         * Get the full url path for the relative URL path.
         *
         * @param relative Relative path to the resource.
         * @return Full URL path including theme, if applicable, for the application to the file.
         */
        buildFullPath(relative) {
            return (this.protocol +
                "//" +
                this.domain +
                ":" +
                this.port +
                this.buildPath(relative));
        }
        /**
         * Build a path relative to the security token
         *
         * @param relative Relative path to the resource.
         * @return Full path to the token relative resource.
         */
        buildTokenPath(relative) {
            return (this.protocol +
                "//" +
                this.domain +
                ":" +
                this.port +
                this.securityToken +
                relative);
        }
    }

    // MIT License
    //
    // Copyright 2021 cPanel L.L.C.
    //
    // Permission is hereby granted, free of charge, to any person obtaining a copy
    //  of this software and associated documentation files (the "Software"), to deal
    // in the Software without restriction, including without limitation the
    // rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    // sell copies of the Software, and to permit persons to whom the Software is
    // furnished to do so, subject to the following conditions:
    //
    // The above copyright notice and this permission notice shall be included in
    // all copies or substantial portions of the Software.
    //
    // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    // FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    // DEALINGS IN THE SOFTWARE.
    /**
     * Provides a mockable layer between the tools below and window.location.
     */
    class LocationService {
        /**
         * The pathname part of the URL.
         */
        get pathname() {
            return window.location.pathname;
        }
        /**
         * The port part of the URL.
         */
        get port() {
            return window.location.port;
        }
        /**
         * The hostname part of the URL.
         */
        get hostname() {
            return window.location.hostname;
        }
        /**
         * The protocol part of the URL.
         */
        get protocol() {
            return window.location.protocol;
        }
    }

    /**
     * A specialized version of `_.reduce` for arrays without support for
     * iteratee shorthands.
     *
     * @private
     * @param {Array} [array] The array to iterate over.
     * @param {Function} iteratee The function invoked per iteration.
     * @param {*} [accumulator] The initial value.
     * @param {boolean} [initAccum] Specify using the first element of `array` as
     *  the initial value.
     * @returns {*} Returns the accumulated value.
     */

    function arrayReduce$1(array, iteratee, accumulator, initAccum) {
      var index = -1,
          length = array == null ? 0 : array.length;

      if (initAccum && length) {
        accumulator = array[++index];
      }
      while (++index < length) {
        accumulator = iteratee(accumulator, array[index], index, array);
      }
      return accumulator;
    }

    var _arrayReduce = arrayReduce$1;

    /**
     * The base implementation of `_.propertyOf` without support for deep paths.
     *
     * @private
     * @param {Object} object The object to query.
     * @returns {Function} Returns the new accessor function.
     */

    function basePropertyOf$1(object) {
      return function(key) {
        return object == null ? undefined : object[key];
      };
    }

    var _basePropertyOf = basePropertyOf$1;

    var basePropertyOf = _basePropertyOf;

    /** Used to map Latin Unicode letters to basic Latin letters. */
    var deburredLetters = {
      // Latin-1 Supplement block.
      '\xc0': 'A',  '\xc1': 'A', '\xc2': 'A', '\xc3': 'A', '\xc4': 'A', '\xc5': 'A',
      '\xe0': 'a',  '\xe1': 'a', '\xe2': 'a', '\xe3': 'a', '\xe4': 'a', '\xe5': 'a',
      '\xc7': 'C',  '\xe7': 'c',
      '\xd0': 'D',  '\xf0': 'd',
      '\xc8': 'E',  '\xc9': 'E', '\xca': 'E', '\xcb': 'E',
      '\xe8': 'e',  '\xe9': 'e', '\xea': 'e', '\xeb': 'e',
      '\xcc': 'I',  '\xcd': 'I', '\xce': 'I', '\xcf': 'I',
      '\xec': 'i',  '\xed': 'i', '\xee': 'i', '\xef': 'i',
      '\xd1': 'N',  '\xf1': 'n',
      '\xd2': 'O',  '\xd3': 'O', '\xd4': 'O', '\xd5': 'O', '\xd6': 'O', '\xd8': 'O',
      '\xf2': 'o',  '\xf3': 'o', '\xf4': 'o', '\xf5': 'o', '\xf6': 'o', '\xf8': 'o',
      '\xd9': 'U',  '\xda': 'U', '\xdb': 'U', '\xdc': 'U',
      '\xf9': 'u',  '\xfa': 'u', '\xfb': 'u', '\xfc': 'u',
      '\xdd': 'Y',  '\xfd': 'y', '\xff': 'y',
      '\xc6': 'Ae', '\xe6': 'ae',
      '\xde': 'Th', '\xfe': 'th',
      '\xdf': 'ss',
      // Latin Extended-A block.
      '\u0100': 'A',  '\u0102': 'A', '\u0104': 'A',
      '\u0101': 'a',  '\u0103': 'a', '\u0105': 'a',
      '\u0106': 'C',  '\u0108': 'C', '\u010a': 'C', '\u010c': 'C',
      '\u0107': 'c',  '\u0109': 'c', '\u010b': 'c', '\u010d': 'c',
      '\u010e': 'D',  '\u0110': 'D', '\u010f': 'd', '\u0111': 'd',
      '\u0112': 'E',  '\u0114': 'E', '\u0116': 'E', '\u0118': 'E', '\u011a': 'E',
      '\u0113': 'e',  '\u0115': 'e', '\u0117': 'e', '\u0119': 'e', '\u011b': 'e',
      '\u011c': 'G',  '\u011e': 'G', '\u0120': 'G', '\u0122': 'G',
      '\u011d': 'g',  '\u011f': 'g', '\u0121': 'g', '\u0123': 'g',
      '\u0124': 'H',  '\u0126': 'H', '\u0125': 'h', '\u0127': 'h',
      '\u0128': 'I',  '\u012a': 'I', '\u012c': 'I', '\u012e': 'I', '\u0130': 'I',
      '\u0129': 'i',  '\u012b': 'i', '\u012d': 'i', '\u012f': 'i', '\u0131': 'i',
      '\u0134': 'J',  '\u0135': 'j',
      '\u0136': 'K',  '\u0137': 'k', '\u0138': 'k',
      '\u0139': 'L',  '\u013b': 'L', '\u013d': 'L', '\u013f': 'L', '\u0141': 'L',
      '\u013a': 'l',  '\u013c': 'l', '\u013e': 'l', '\u0140': 'l', '\u0142': 'l',
      '\u0143': 'N',  '\u0145': 'N', '\u0147': 'N', '\u014a': 'N',
      '\u0144': 'n',  '\u0146': 'n', '\u0148': 'n', '\u014b': 'n',
      '\u014c': 'O',  '\u014e': 'O', '\u0150': 'O',
      '\u014d': 'o',  '\u014f': 'o', '\u0151': 'o',
      '\u0154': 'R',  '\u0156': 'R', '\u0158': 'R',
      '\u0155': 'r',  '\u0157': 'r', '\u0159': 'r',
      '\u015a': 'S',  '\u015c': 'S', '\u015e': 'S', '\u0160': 'S',
      '\u015b': 's',  '\u015d': 's', '\u015f': 's', '\u0161': 's',
      '\u0162': 'T',  '\u0164': 'T', '\u0166': 'T',
      '\u0163': 't',  '\u0165': 't', '\u0167': 't',
      '\u0168': 'U',  '\u016a': 'U', '\u016c': 'U', '\u016e': 'U', '\u0170': 'U', '\u0172': 'U',
      '\u0169': 'u',  '\u016b': 'u', '\u016d': 'u', '\u016f': 'u', '\u0171': 'u', '\u0173': 'u',
      '\u0174': 'W',  '\u0175': 'w',
      '\u0176': 'Y',  '\u0177': 'y', '\u0178': 'Y',
      '\u0179': 'Z',  '\u017b': 'Z', '\u017d': 'Z',
      '\u017a': 'z',  '\u017c': 'z', '\u017e': 'z',
      '\u0132': 'IJ', '\u0133': 'ij',
      '\u0152': 'Oe', '\u0153': 'oe',
      '\u0149': "'n", '\u017f': 's'
    };

    /**
     * Used by `_.deburr` to convert Latin-1 Supplement and Latin Extended-A
     * letters to basic Latin letters.
     *
     * @private
     * @param {string} letter The matched letter to deburr.
     * @returns {string} Returns the deburred letter.
     */
    var deburrLetter$1 = basePropertyOf(deburredLetters);

    var _deburrLetter = deburrLetter$1;

    /**
     * A specialized version of `_.map` for arrays without support for iteratee
     * shorthands.
     *
     * @private
     * @param {Array} [array] The array to iterate over.
     * @param {Function} iteratee The function invoked per iteration.
     * @returns {Array} Returns the new mapped array.
     */

    function arrayMap$1(array, iteratee) {
      var index = -1,
          length = array == null ? 0 : array.length,
          result = Array(length);

      while (++index < length) {
        result[index] = iteratee(array[index], index, array);
      }
      return result;
    }

    var _arrayMap = arrayMap$1;

    var baseGetTag = _baseGetTag,
        isObjectLike = isObjectLike_1;

    /** `Object#toString` result references. */
    var symbolTag = '[object Symbol]';

    /**
     * Checks if `value` is classified as a `Symbol` primitive or object.
     *
     * @static
     * @memberOf _
     * @since 4.0.0
     * @category Lang
     * @param {*} value The value to check.
     * @returns {boolean} Returns `true` if `value` is a symbol, else `false`.
     * @example
     *
     * _.isSymbol(Symbol.iterator);
     * // => true
     *
     * _.isSymbol('abc');
     * // => false
     */
    function isSymbol$1(value) {
      return typeof value == 'symbol' ||
        (isObjectLike(value) && baseGetTag(value) == symbolTag);
    }

    var isSymbol_1 = isSymbol$1;

    var Symbol = _Symbol,
        arrayMap = _arrayMap,
        isArray = isArray_1,
        isSymbol = isSymbol_1;

    /** Used as references for various `Number` constants. */
    var INFINITY = 1 / 0;

    /** Used to convert symbols to primitives and strings. */
    var symbolProto = Symbol ? Symbol.prototype : undefined,
        symbolToString = symbolProto ? symbolProto.toString : undefined;

    /**
     * The base implementation of `_.toString` which doesn't convert nullish
     * values to empty strings.
     *
     * @private
     * @param {*} value The value to process.
     * @returns {string} Returns the string.
     */
    function baseToString$1(value) {
      // Exit early for strings to avoid a performance hit in some environments.
      if (typeof value == 'string') {
        return value;
      }
      if (isArray(value)) {
        // Recursively convert values (susceptible to call stack limits).
        return arrayMap(value, baseToString$1) + '';
      }
      if (isSymbol(value)) {
        return symbolToString ? symbolToString.call(value) : '';
      }
      var result = (value + '');
      return (result == '0' && (1 / value) == -INFINITY) ? '-0' : result;
    }

    var _baseToString = baseToString$1;

    var baseToString = _baseToString;

    /**
     * Converts `value` to a string. An empty string is returned for `null`
     * and `undefined` values. The sign of `-0` is preserved.
     *
     * @static
     * @memberOf _
     * @since 4.0.0
     * @category Lang
     * @param {*} value The value to convert.
     * @returns {string} Returns the converted string.
     * @example
     *
     * _.toString(null);
     * // => ''
     *
     * _.toString(-0);
     * // => '-0'
     *
     * _.toString([1, 2, 3]);
     * // => '1,2,3'
     */
    function toString$2(value) {
      return value == null ? '' : baseToString(value);
    }

    var toString_1 = toString$2;

    var deburrLetter = _deburrLetter,
        toString$1 = toString_1;

    /** Used to match Latin Unicode letters (excluding mathematical operators). */
    var reLatin = /[\xc0-\xd6\xd8-\xf6\xf8-\xff\u0100-\u017f]/g;

    /** Used to compose unicode character classes. */
    var rsComboMarksRange$1 = '\\u0300-\\u036f',
        reComboHalfMarksRange$1 = '\\ufe20-\\ufe2f',
        rsComboSymbolsRange$1 = '\\u20d0-\\u20ff',
        rsComboRange$1 = rsComboMarksRange$1 + reComboHalfMarksRange$1 + rsComboSymbolsRange$1;

    /** Used to compose unicode capture groups. */
    var rsCombo$1 = '[' + rsComboRange$1 + ']';

    /**
     * Used to match [combining diacritical marks](https://en.wikipedia.org/wiki/Combining_Diacritical_Marks) and
     * [combining diacritical marks for symbols](https://en.wikipedia.org/wiki/Combining_Diacritical_Marks_for_Symbols).
     */
    var reComboMark = RegExp(rsCombo$1, 'g');

    /**
     * Deburrs `string` by converting
     * [Latin-1 Supplement](https://en.wikipedia.org/wiki/Latin-1_Supplement_(Unicode_block)#Character_table)
     * and [Latin Extended-A](https://en.wikipedia.org/wiki/Latin_Extended-A)
     * letters to basic Latin letters and removing
     * [combining diacritical marks](https://en.wikipedia.org/wiki/Combining_Diacritical_Marks).
     *
     * @static
     * @memberOf _
     * @since 3.0.0
     * @category String
     * @param {string} [string=''] The string to deburr.
     * @returns {string} Returns the deburred string.
     * @example
     *
     * _.deburr('déjà vu');
     * // => 'deja vu'
     */
    function deburr$1(string) {
      string = toString$1(string);
      return string && string.replace(reLatin, deburrLetter).replace(reComboMark, '');
    }

    var deburr_1 = deburr$1;

    /** Used to match words composed of alphanumeric characters. */

    var reAsciiWord = /[^\x00-\x2f\x3a-\x40\x5b-\x60\x7b-\x7f]+/g;

    /**
     * Splits an ASCII `string` into an array of its words.
     *
     * @private
     * @param {string} The string to inspect.
     * @returns {Array} Returns the words of `string`.
     */
    function asciiWords$1(string) {
      return string.match(reAsciiWord) || [];
    }

    var _asciiWords = asciiWords$1;

    /** Used to detect strings that need a more robust regexp to match words. */

    var reHasUnicodeWord = /[a-z][A-Z]|[A-Z]{2}[a-z]|[0-9][a-zA-Z]|[a-zA-Z][0-9]|[^a-zA-Z0-9 ]/;

    /**
     * Checks if `string` contains a word composed of Unicode symbols.
     *
     * @private
     * @param {string} string The string to inspect.
     * @returns {boolean} Returns `true` if a word is found, else `false`.
     */
    function hasUnicodeWord$1(string) {
      return reHasUnicodeWord.test(string);
    }

    var _hasUnicodeWord = hasUnicodeWord$1;

    /** Used to compose unicode character classes. */

    var rsAstralRange = '\\ud800-\\udfff',
        rsComboMarksRange = '\\u0300-\\u036f',
        reComboHalfMarksRange = '\\ufe20-\\ufe2f',
        rsComboSymbolsRange = '\\u20d0-\\u20ff',
        rsComboRange = rsComboMarksRange + reComboHalfMarksRange + rsComboSymbolsRange,
        rsDingbatRange = '\\u2700-\\u27bf',
        rsLowerRange = 'a-z\\xdf-\\xf6\\xf8-\\xff',
        rsMathOpRange = '\\xac\\xb1\\xd7\\xf7',
        rsNonCharRange = '\\x00-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7b-\\xbf',
        rsPunctuationRange = '\\u2000-\\u206f',
        rsSpaceRange = ' \\t\\x0b\\f\\xa0\\ufeff\\n\\r\\u2028\\u2029\\u1680\\u180e\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200a\\u202f\\u205f\\u3000',
        rsUpperRange = 'A-Z\\xc0-\\xd6\\xd8-\\xde',
        rsVarRange = '\\ufe0e\\ufe0f',
        rsBreakRange = rsMathOpRange + rsNonCharRange + rsPunctuationRange + rsSpaceRange;

    /** Used to compose unicode capture groups. */
    var rsApos$1 = "['\u2019]",
        rsBreak = '[' + rsBreakRange + ']',
        rsCombo = '[' + rsComboRange + ']',
        rsDigits = '\\d+',
        rsDingbat = '[' + rsDingbatRange + ']',
        rsLower = '[' + rsLowerRange + ']',
        rsMisc = '[^' + rsAstralRange + rsBreakRange + rsDigits + rsDingbatRange + rsLowerRange + rsUpperRange + ']',
        rsFitz = '\\ud83c[\\udffb-\\udfff]',
        rsModifier = '(?:' + rsCombo + '|' + rsFitz + ')',
        rsNonAstral = '[^' + rsAstralRange + ']',
        rsRegional = '(?:\\ud83c[\\udde6-\\uddff]){2}',
        rsSurrPair = '[\\ud800-\\udbff][\\udc00-\\udfff]',
        rsUpper = '[' + rsUpperRange + ']',
        rsZWJ = '\\u200d';

    /** Used to compose unicode regexes. */
    var rsMiscLower = '(?:' + rsLower + '|' + rsMisc + ')',
        rsMiscUpper = '(?:' + rsUpper + '|' + rsMisc + ')',
        rsOptContrLower = '(?:' + rsApos$1 + '(?:d|ll|m|re|s|t|ve))?',
        rsOptContrUpper = '(?:' + rsApos$1 + '(?:D|LL|M|RE|S|T|VE))?',
        reOptMod = rsModifier + '?',
        rsOptVar = '[' + rsVarRange + ']?',
        rsOptJoin = '(?:' + rsZWJ + '(?:' + [rsNonAstral, rsRegional, rsSurrPair].join('|') + ')' + rsOptVar + reOptMod + ')*',
        rsOrdLower = '\\d*(?:1st|2nd|3rd|(?![123])\\dth)(?=\\b|[A-Z_])',
        rsOrdUpper = '\\d*(?:1ST|2ND|3RD|(?![123])\\dTH)(?=\\b|[a-z_])',
        rsSeq = rsOptVar + reOptMod + rsOptJoin,
        rsEmoji = '(?:' + [rsDingbat, rsRegional, rsSurrPair].join('|') + ')' + rsSeq;

    /** Used to match complex or compound words. */
    var reUnicodeWord = RegExp([
      rsUpper + '?' + rsLower + '+' + rsOptContrLower + '(?=' + [rsBreak, rsUpper, '$'].join('|') + ')',
      rsMiscUpper + '+' + rsOptContrUpper + '(?=' + [rsBreak, rsUpper + rsMiscLower, '$'].join('|') + ')',
      rsUpper + '?' + rsMiscLower + '+' + rsOptContrLower,
      rsUpper + '+' + rsOptContrUpper,
      rsOrdUpper,
      rsOrdLower,
      rsDigits,
      rsEmoji
    ].join('|'), 'g');

    /**
     * Splits a Unicode `string` into an array of its words.
     *
     * @private
     * @param {string} The string to inspect.
     * @returns {Array} Returns the words of `string`.
     */
    function unicodeWords$1(string) {
      return string.match(reUnicodeWord) || [];
    }

    var _unicodeWords = unicodeWords$1;

    var asciiWords = _asciiWords,
        hasUnicodeWord = _hasUnicodeWord,
        toString = toString_1,
        unicodeWords = _unicodeWords;

    /**
     * Splits `string` into an array of its words.
     *
     * @static
     * @memberOf _
     * @since 3.0.0
     * @category String
     * @param {string} [string=''] The string to inspect.
     * @param {RegExp|string} [pattern] The pattern to match words.
     * @param- {Object} [guard] Enables use as an iteratee for methods like `_.map`.
     * @returns {Array} Returns the words of `string`.
     * @example
     *
     * _.words('fred, barney, & pebbles');
     * // => ['fred', 'barney', 'pebbles']
     *
     * _.words('fred, barney, & pebbles', /[^, ]+/g);
     * // => ['fred', 'barney', '&', 'pebbles']
     */
    function words$1(string, pattern, guard) {
      string = toString(string);
      pattern = guard ? undefined : pattern;

      if (pattern === undefined) {
        return hasUnicodeWord(string) ? unicodeWords(string) : asciiWords(string);
      }
      return string.match(pattern) || [];
    }

    var words_1 = words$1;

    var arrayReduce = _arrayReduce,
        deburr = deburr_1,
        words = words_1;

    /** Used to compose unicode capture groups. */
    var rsApos = "['\u2019]";

    /** Used to match apostrophes. */
    var reApos = RegExp(rsApos, 'g');

    /**
     * Creates a function like `_.camelCase`.
     *
     * @private
     * @param {Function} callback The function to combine each word.
     * @returns {Function} Returns the new compounder function.
     */
    function createCompounder$1(callback) {
      return function(string) {
        return arrayReduce(words(deburr(string).replace(reApos, '')), callback, '');
      };
    }

    var _createCompounder = createCompounder$1;

    var createCompounder = _createCompounder;

    /**
     * Converts `string` to
     * [snake case](https://en.wikipedia.org/wiki/Snake_case).
     *
     * @static
     * @memberOf _
     * @since 3.0.0
     * @category String
     * @param {string} [string=''] The string to convert.
     * @returns {string} Returns the snake cased string.
     * @example
     *
     * _.snakeCase('Foo Bar');
     * // => 'foo_bar'
     *
     * _.snakeCase('fooBar');
     * // => 'foo_bar'
     *
     * _.snakeCase('--FOO-BAR--');
     * // => 'foo_bar'
     */
    var snakeCase = createCompounder(function(result, word, index) {
      return result + (index ? '_' : '') + word.toLowerCase();
    });

    var snakeCase_1 = snakeCase;

    var snakeCase$1 = /*@__PURE__*/getDefaultExportFromCjs(snakeCase_1);

    // MIT License
    class UapiRequest extends Request {
        /**
         * Add a custom HTTP header to the request
         *
         * @param name Name of a column
         * @return Updated Request object.
         */
        addHeader(header) {
            if (header instanceof WhmApiTokenHeader) {
                throw new WhmApiTokenMismatchError("A WhmApiTokenHeader cannot be used on a CpanelApiRequest");
            }
            super.addHeader(header);
            return this;
        }
        /**
         * Build a fragment of the parameter list based on the list of name/value pairs.
         *
         * @param params  Parameters to serialize.
         * @param encoder Encoder to use to serialize the each parameter.
         * @return Fragment with the serialized parameters
         */
        _build(params, encoder) {
            let fragment = "";
            params.forEach((arg, index, array) => {
                const isLast = index === array.length - 1;
                fragment += encoder.encode(arg.name, arg.value, isLast);
            });
            return encoder.separatorStart + fragment + encoder.separatorEnd;
        }
        /**
         * Generates the arguments for the request.
         *
         * @param params List of parameters to adjust based on the sort rules in the Request.
         */
        _generateArguments(params) {
            this.arguments.forEach((argument) => params.push(argument));
        }
        /**
         * Generates the sort parameters for the request.
         *
         * @param params List of parameters to adjust based on the sort rules in the Request.
         */
        _generateSorts(params) {
            this.sorts.forEach((sort, index) => {
                if (index === 0) {
                    params.push({
                        name: "api.sort",
                        value: fromBoolean(true),
                    });
                }
                params.push({
                    name: "api.sort_column_" + index,
                    value: sort.column,
                });
                params.push({
                    name: "api.sort_reverse_" + index,
                    value: fromBoolean(sort.direction !== SortDirection.Ascending),
                });
                params.push({
                    name: "api.sort_method_" + index,
                    value: snakeCase$1(SortType[sort.type]),
                });
            });
        }
        /**
         * Look up the correct name for the filter operator
         *
         * @param operator Type of filter operator to use to filter the items
         * @returns The string counter part for the filter operator.
         * @throws Will throw an error if an unrecognized FilterOperator is provided.
         */
        _lookupFilterOperator(operator) {
            switch (operator) {
                case FilterOperator.GreaterThanUnlimited:
                    return "gt_handle_unlimited";
                case FilterOperator.GreaterThan:
                    return "gt";
                case FilterOperator.LessThanUnlimited:
                    return "lt_handle_unlimited";
                case FilterOperator.LessThan:
                    return "lt";
                case FilterOperator.NotEqual:
                    return "ne";
                case FilterOperator.Equal:
                    return "eq";
                case FilterOperator.Defined:
                    return "defined";
                case FilterOperator.Undefined:
                    return "undefined";
                case FilterOperator.Matches:
                    return "matches";
                case FilterOperator.Ends:
                    return "ends";
                case FilterOperator.Begins:
                    return "begins";
                case FilterOperator.Contains:
                    return "contains";
                default:
                    // eslint-disable-next-line no-case-declarations -- just used for readability
                    const key = FilterOperator[operator];
                    throw new Error(`Unrecognized FilterOperator ${key} for UAPI`);
            }
        }
        /**
         * Generate the filter parameters if any.
         *
         * @param params List of parameters to adjust based on the filter rules provided.
         */
        _generateFilters(params) {
            this.filters.forEach((filter, index) => {
                params.push({
                    name: "api.filter_column_" + index,
                    value: filter.column,
                });
                params.push({
                    name: "api.filter_type_" + index,
                    value: this._lookupFilterOperator(filter.operator),
                });
                params.push({
                    name: "api.filter_term_" + index,
                    value: filter.value,
                });
            });
        }
        /**
         * In UAPI, we request the starting record, not the starting page. This translates
         * the page and page size into the correct starting record.
         */
        _traslatePageToStart(pager) {
            return (pager.page - 1) * pager.pageSize + 1;
        }
        /**
         * Generate the pager request parameters, if any.
         *
         * @param params List of parameters to adjust based on the pagination rules.
         */
        _generatePagination(params) {
            if (!this.usePager) {
                return;
            }
            const allPages = this.pager.all();
            params.push({
                name: "api.paginate",
                value: fromBoolean(true),
            });
            params.push({
                name: "api.paginate_start",
                value: allPages ? -1 : this._traslatePageToStart(this.pager),
            });
            if (!allPages) {
                params.push({
                    name: "api.paginate_size",
                    value: this.pager.pageSize,
                });
            }
        }
        /**
         * Generate any additional parameters from the configuration data.
         *
         * @param params List of parameters to adjust based on the configuration.
         */
        _generateConfiguration(params) {
            if (this.config && this.config["analytics"]) {
                params.push({
                    name: "api.analytics",
                    value: fromBoolean(this.config.analytics),
                });
            }
        }
        /**
         * Create a new uapi request.
         *
         * @param init  Optional request objects used to initialize this object.
         */
        constructor(init) {
            super(init);
        }
        /**
         * Generate the interchange object that has the pre-encoded
         * request using UAPI formatting.
         *
         * @param rule Optional parameter to specify a specific Rule we want the Request to be generated for.
         * @return Request information ready to be used by a remoting layer
         */
        generate(rule) {
            // Needed for pure JS clients, since they don't get the compiler checks
            if (!this.namespace) {
                throw new Error("You must define a namespace for the UAPI call before you generate a request");
            }
            if (!this.method) {
                throw new Error("You must define a method for the UAPI call before you generate a request");
            }
            if (!rule) {
                rule = {
                    verb: HttpVerb.POST,
                    encoder: this.config.json
                        ? new JsonArgumentEncoder()
                        : new WwwFormUrlArgumentEncoder(),
                };
            }
            if (!rule.encoder) {
                rule.encoder = this.config.json
                    ? new JsonArgumentEncoder()
                    : new WwwFormUrlArgumentEncoder();
            }
            const argumentRule = argumentSerializationRules.getRule(rule.verb);
            const info = {
                headers: new Headers([
                    {
                        name: "Content-Type",
                        value: rule.encoder.contentType,
                    },
                ]),
                url: ["", "execute", this.namespace, this.method]
                    .map(encodeURIComponent)
                    .join("/"),
                body: "",
            };
            const params = [];
            this._generateArguments(params);
            this._generateSorts(params);
            this._generateFilters(params);
            this._generatePagination(params);
            this._generateConfiguration(params);
            const encoded = this._build(params, rule.encoder);
            if (argumentRule.dataInBody) {
                info["body"] = encoded;
            }
            else {
                if (rule.verb === HttpVerb.GET) {
                    info["url"] += `?${encoded}`;
                }
                else {
                    info["url"] += encoded;
                }
            }
            this.headers.forEach((header) => {
                info.headers.push({
                    name: header.name,
                    value: header.value,
                });
            });
            return info;
        }
    }

    // MIT License
    /**
     * This class will extract the available metadata from the UAPI format into a standard format for JavaScript developers.
     */
    class UapiMetaData {
        /**
         * Build a new MetaData object from the metadata response from the server.
         *
         * @param meta UAPI metadata object.
         */
        constructor(meta) {
            /**
             * Indicates if the data is paged.
             */
            this.isPaged = false;
            /**
             * The record number of the first record of a page.
             */
            this.record = 0;
            /**
             * The current page.
             */
            this.page = 0;
            /**
             * The page size of the returned set.
             */
            this.pageSize = 0;
            /**
             * The total number of records available on the backend.
             */
            this.totalRecords = 0;
            /**
             * The total number of pages of records on the backend.
             */
            this.totalPages = 0;
            /**
             * Indicates if the data set if filtered.
             */
            this.isFiltered = false;
            /**
             * Number of records available before the filter was processed.
             */
            this.recordsBeforeFilter = 0;
            /**
             * Indicates the response was the result of a batch API.
             */
            this.batch = false;
            /**
             * A collection of the other less common or custom UAPI metadata properties.
             */
            this.properties = {};
            // Handle pagination
            if (meta.paginate) {
                this.isPaged = true;
                this.record = parseInt(meta.paginate.start_result, 10) || 0;
                this.page = parseInt(meta.paginate.current_page, 10) || 0;
                this.pageSize = parseInt(meta.paginate.results_per_page, 10) || 0;
                this.totalPages = parseInt(meta.paginate.total_pages, 10) || 0;
                this.totalRecords = parseInt(meta.paginate.total_results, 10) || 0;
            }
            // Handle filtering
            if (meta.filter) {
                this.isFiltered = true;
                this.recordsBeforeFilter =
                    parseInt(meta.filter.records_before_filter, 10) || 0;
            }
            // Get any other custom metadata properties off the object
            const builtinSet = new Set(["paginate", "filter"]);
            Object.keys(meta)
                .filter((key) => !builtinSet.has(key))
                .forEach((key) => {
                this.properties[key] = meta[key];
            });
        }
    }
    /**
     * Parser that will convert a UAPI wire-formated object into a standard response object for JavaScript developers.
     */
    class UapiResponse extends Response {
        /**
         * Parse out the status from the response.
         *
         * @param  response Raw response object from the backend. Already passed through JSON.parse().
         * @return Number indicating success or failure. > 1 success, 0 failure.
         */
        _parseStatus(response) {
            this.status = 0; // Assume it failed.
            if (typeof response.status === "undefined") {
                throw new Error("The response should have a numeric status property indicating the API succeeded (>0) or failed (=0)");
            }
            this.status = parseInt(response.status, 10);
        }
        /**
         * Parse out the messages from the response.
         *
         * @param response The response object sent by the API method.
         */
        _parseMessages(response) {
            if ("errors" in response) {
                const errors = response.errors;
                if (errors && errors.length) {
                    errors.forEach((error) => {
                        this.messages.push({
                            type: MessageType.Error,
                            message: error,
                        });
                    });
                }
            }
            if ("messages" in response) {
                const messages = response.messages;
                if (messages) {
                    messages.forEach((message) => {
                        this.messages.push({
                            type: MessageType.Information,
                            message: message,
                        });
                    });
                }
            }
        }
        /**
         * Parse out the status, data and metadata from a UAPI response into the abstract Response and IMetaData structures.
         *
         * @param response  Raw response from the server. It's just been JSON.parse() at this point.
         * @param Options on how to handle parsing of the response.
         */
        constructor(response, options) {
            super(response, options);
            this._parseStatus(response);
            this._parseMessages(response);
            if (!response ||
                !Object.prototype.hasOwnProperty.call(response, "data")) {
                throw new Error("Expected response to contain a data property, but it is missing");
            }
            // TODO: Add parsing by specific types to take care of renames and type coercion.
            this.data = response.data;
            if (response.metadata) {
                this.meta = new UapiMetaData(response.metadata);
            }
        }
    }

    const componentElName = "cp-koality-sidebar-app";
    const componentName = "cpanel-koality-sidebar-app";
    const type = "campaign";
    const campaignStartDate = "6.10.24";
    const campaignId = `${type}.${componentName}.${campaignStartDate}`;
    const application = "cPanel";
    const appName = "tools";
    const dismissedId = `${campaignId}-dismissed`;

    /**
     * Map the relative url into a fully specified url suitable for use in cpanel.
     *
     * @param {string} url
     * @returns {string}
     */
    const expandUrl = (relativeUrl) => {
        const appPath = new ApplicationPath(new LocationService());
        return appPath.buildTokenPath(relativeUrl);
    };

    /**
     * Parse a raw response into a UapiResponse.
     *
     * @param {object} response
     * @param {string} url
     * @returns {UapiResponse}
     */
    const parseResponse = (response, url) => {
        const uapiResponse = new UapiResponse(response);
        uapiResponse.meta.properties.url = url ? url : "";
        return uapiResponse;
    };

    /**
     * Run an api call.
     *
     * @async
     * @param {string} url
     * @param {*} options
     * @returns {Promise}
     */
    const fetchData = (url, options) => fetch(url, options)
        .then((response) => {
            if (!response.ok) {
                throw new Error(`HTTP error ${response.status}`);
            }

            return response.json();
        })
        .then((data) => {
            const response = parseResponse(data);
            if (response.hasErrors) {
                return Promise.reject(response.errors);
            }

            return Promise.resolve(response);
        })
        .catch(console.error);


    /**
     * Custom web component for koality cpanel homepage right sidebar.
     *
     * @example This web component can be created in Markup:
     *
     *  <cp-koality-sidebar-app
     *      bodyTitle="Title"
     *      bodyText="Message"
     *      closeTitle="Close"
     *      buttonLabel="Submit">
     *  </cp-koality-sidebar-app>
     *
     * @example This web component can be created in JS code:
     *
     *   const el = document.createElement('cp-koality-sidebar-app');
     *   el.setAttribute('bodyTitle', 'Title');
     *   el.setAttribute('bodyText', 'Message');
     *   el.setAttribute('closeTitle', 'Close');
     *   el.setAttribute('buttonLabel', 'Submit');
     *
     * @extends HTMLElement
     */
    class KoalitySidebarApp extends HTMLElement {

        /**
         * Create a new KoalitySidebarApp
         */
        constructor() {
            super();
            this.attachShadow({
                mode: "open",
            });
            this.loadContent();
            this.addListeners();
            this.setupObserver();
        }

        /**
         * Load the template and style into the shadowdom and configure the dialogs text.
         *
         * @private
         */
        loadContent() {
            const getAttr = (attr, def) => this.getAttribute(attr) || def;

            const template = document.createElement("template");
            const styles = document.createElement("style");

            styles.textContent += cssReset;
            styles.textContent += css;

            template.innerHTML = html;
            template.content.prepend(styles);
            this.shadowRoot.appendChild(template.content.cloneNode(true));

            const titleEl = this.shadowRoot.querySelector("#title");
            titleEl.innerHTML = getAttr("bodyTitle");

            const bodyEl = this.shadowRoot.querySelector("#body");
            bodyEl.innerHTML = getAttr("bodyText");

            const buttonEl = this.shadowRoot.querySelector("#button-cta");
            buttonEl.innerHTML = getAttr("buttonLabel");

            const closeEl = this.shadowRoot.querySelector("#close");
            closeEl.title = getAttr("closeTitle");
        }

        /**
         * Track the event in analytics.
         *
         * @private
         * @param {string} action
         * @param {string} elementId
         */
        trackEvent(action, elementId) {
            window["mixpanel"]?.track(
                `${application}-${appName}-${campaignId}.${action}`,
                {
                    "campaign_id": campaignId,
                    "action": action.toLowerCase(),
                    "id": elementId,
                }
            );
        }

        /**
         * Add various event handlers to the DOM.
         *
         * @private
         */
        addListeners() {
            const buttonEl = this.shadowRoot.querySelector("#button-cta");
            const buttonAnimationEl = this.shadowRoot.querySelector("#button-cta i");
            const closeEl = this.shadowRoot.querySelector("#close");

            buttonEl?.addEventListener("click", (event) => {
                this.trackEvent("click", event.target.id);
                window.location.href = "../jupiter/koality/signup/index.html";
                buttonAnimationEl.className = "loading-animation";
                setTimeout(() => {
                    buttonAnimationEl.className = "";
                }, 10000);
            });

            closeEl?.addEventListener("click", (event) => {
                this.trackEvent("close", event.target.id);
                this.parentElement.parentElement.remove();
                this.saveDismissedState();
            });
        }

        /**
         * Setup the view observer for the campaign.
         *
         * @private
         */
        setupObserver() {
            const instersectionOptions = {
                threshold: 0.75,
            };
            const intersectionCallback = (intersectionEntries, intersectionObserver) => {
                intersectionEntries.forEach((intersection) => {
                    if (intersection.isIntersecting) {
                        this.trackEvent("view", this.id);
                        intersectionObserver.unobserve(this);
                    }            });
            };
            const intersectionObserver = new IntersectionObserver(intersectionCallback, instersectionOptions);

            intersectionObserver.observe(this);
        }

        /**
         * Save the dismissed state when the dialog is closed.
         *
         * @async
         * @returns {Promise}
         */
        saveDismissedState() {
            const request = new UapiRequest({
                namespace: "Personalization",
                method: "set",
                arguments: [
                    new Argument("personalization", {
                        [ dismissedId ]: true,
                    }),
                ],
                config: {
                    json: true,
                },
            });
            const info = request.generate();
            const url = expandUrl(info.url);
            const options = {
                method: "POST",
                headers: info.headers.toObject(),
                body: info.body,
            };

            return fetchData(url, options);
        }

        /**
         * Fetch the dismissed state from storage.
         *
         * @static
         * @async
         * @returns {Promise}
         */
        static getDismissedState() {
            const request = new UapiRequest({
                namespace: "Personalization",
                method: "get",
                arguments: [
                    new Argument("names", [ dismissedId ]),
                ],
                config: {
                    json: true,
                },
            });
            const info = request.generate();
            const url = expandUrl(info.url);
            const options = {
                method: "POST",
                headers: info.headers.toObject(),
                body: info.body,
            };

            return fetchData(url, options);
        }

        /**
         * Fetch the template from the script block and insert it into the sidebar for cPanel.
         *
         * Note: If the banner was dismissed previously, the banner will not be shown again.
         *
         * @static
         * @async
         */
        static async placeInSidebar() {
            const dismissedState = await this.getDismissedState();
            const bannerClosed = dismissedState?.data?.personalization[
                 dismissedId
            ]?.value;

            if (bannerClosed) {
                return;
            }

            const koalityBannerTemplateEl = document.getElementById("cp-koality-sidebar-app-template");

            const koalityBannerEl = document.createElement("div");
            koalityBannerEl.innerHTML = koalityBannerTemplateEl.innerHTML;
            koalityBannerEl.firstChild.id = campaignId;

            const row = document.createElement("tr");
            const cell = document.createElement("td");

            cell.style.padding = "10px";
            cell.appendChild(koalityBannerEl);
            row.appendChild(cell);

            const login = document.getElementById("lblLastLogin");
            const loginParent = login?.parentElement?.parentElement;
            loginParent?.insertAdjacentElement("afterend", row);
        }
    }

    customElements.define(componentElName, KoalitySidebarApp);
    KoalitySidebarApp.placeInSidebar();

}));
