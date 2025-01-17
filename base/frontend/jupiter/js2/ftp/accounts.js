/* globals LANG, FTP_ACCOUNTS_MAXED, REQUIRED_PASSWORD_STRENGTH, DNS, SERVER_TYPE, CPANEL_USER */
/* globals FTP_SERVER, SFTP_PORT, FTP_PORT */
// UAPI: note that this module has been converted to the UAPI JSON call
/* eslint-disable camelcase */
var OPEN_MODULE;
var PATH_POPUPS = [];
var ADD_VALID = [];
var CHANGE_PASS_VALID = [];
var CHANGE_QUOTA_VALID = [];
var FTP_UAPI_CALL = {};
var TABLE_REQUEST_ACTIVE = false;
var LAST_SEARCH_TXT = "";
var PURE_ACCOUNTS_TABLE_COLUMNS = 4;
var PURE_SPECIAL_ACCOUNTS_TABLE_COLUMNS = 5;
var PRO_ACCOUNTS_TABLE_COLUMNS = 3;
var PRO_SPECIAL_ACCOUNTS_TABLE_COLUMNS = 4;

var FTP_CLIENTS = [
    {
        id: "coreftp",
        name: "CoreFTP",
        os: "Windows"
    }, {
        id: "cyberduck",
        name: "Cyberduck",
        os: "Mac"
    }
];

var changePasswordTpl = Handlebars.compile(DOM.get("change-password-template").text.trim()),
    changeQuotaTpl = Handlebars.compile(DOM.get("change-quota-template").text.trim()),
    deleteAccountTpl = Handlebars.compile(DOM.get("delete-account-template").text.trim()),
    configureClientTpl = Handlebars.compile(DOM.get("configure-client-template").text.trim());

// NOTE: This is needed because IE9 and below do not support
// innerHTML on table, tbody, thead, and tr elements.
// This should be removed when we end support for IE9.
var tbody_placeholder = document.createElement("div");
var requiresInnerHTMLFix;
var tableInnerHTMLTestElement = document.createElement("table");
try {
    tableInnerHTMLTestElement.innerHTML = "<tbody></tbody>";
} catch (e) {
} finally {
    requiresInnerHTMLFix = (tableInnerHTMLTestElement.childNodes.length === 0);
}

var insert_html_into_table = function(table_id, html) {

    // NOTE: The first block should be removed once we end support for IE9.
    var tbody = document.getElementById(table_id);
    if (requiresInnerHTMLFix) {
        var table = tbody.parentNode;
        tbody_placeholder.innerHTML = "<table><tbody id=\"" + table_id + "\">" + html + "</tbody></table>";
        table.replaceChild(tbody_placeholder.firstChild.firstChild, table.tBodies[0]);
    } else {
        tbody.innerHTML = html;
    }
};

var generate_table_message = function(table_id, type, message, number_of_cols) {
    var html = "<tr class=\"" + type + " empty-row\">" +
        "<td colspan=\"" + number_of_cols + "\">" + message + "</td>" +
        "</tr>";
    insert_html_into_table(table_id, html);
};

var init_add_validation = function() {
    var DOM = YAHOO.util.Dom;
    var domain_el = DOM.get("domain");
    ADD_VALID["login"] = new CPANEL.validate.validator(LANG.ftp_login);
    ADD_VALID["login"].add("login", "min_length(%input%, 1)", LOCALE.maketext("You must enter an [output,acronym,FTP,File Transfer Protocol] username."), null, { unique_id: "username_min_length" });
    ADD_VALID["login"].add("login", "max_length(%input%, 64)", LOCALE.maketext("The [output,acronym,FTP,File Transfer Protocol] username cannot exceed [numf,_1] characters.", 64), null, { unique_id: "username_max_length" });
    ADD_VALID["login"].add("login", function(login_el) {
        var username = login_el.value + "@" + domain_el.value;
        return CPANEL.validate.max_length(username, 254);
    },
    LOCALE.maketext("The full [output,acronym,FTP,File Transfer Protocol] username with its associated domain cannot exceed [numf,_1] characters.", 254),
    null,
    { unique_id: "username_full_length" }
    );
    ADD_VALID["login"].add("login", "ftp_username", LOCALE.maketext("You can only enter letters [asis,(a-z)], numbers [asis,(0-9)], periods, hyphens [asis,(-)], and underscores [asis,(_)]."), null, { unique_id: "username_valid" });
    ADD_VALID["login"].add("login", "no_unsafe_periods", LOCALE.maketext("The [output,acronym,FTP,File Transfer Protocol] username cannot start with a period, end with a period, or include two consecutive periods."), null, { unique_id: "username_safe_periods" });
    ADD_VALID["login"].attach();

    ADD_VALID["domain"] = new CPANEL.validate.validator(LANG.ftp_domain);
    ADD_VALID["domain"].add("domain", function() {
        ADD_VALID["login"].clear_messages();
        ADD_VALID["login"].verify(); // Will show up in the local parts validator
        return true;                      // So this always passes
    }, ""
    );
    ADD_VALID["domain"].attach();

    var password_validators = CPANEL.password.setup("password", "password2", "password_strength", REQUIRED_PASSWORD_STRENGTH, "create_strong_password", "why_strong_passwords_link", "why_strong_passwords_text");
    ADD_VALID["pass1"] = password_validators[0];
    ADD_VALID["pass2"] = password_validators[1];

    ADD_VALID["dir"] = new CPANEL.validate.validator(LANG.directory_path);
    ADD_VALID["dir"].add("homedir", "dir_path", LANG.validation_directory_paths);
    ADD_VALID["dir"].attach();

    if (SERVER_TYPE !== "PRO") {
        ADD_VALID["quota_number"] = new CPANEL.validate.validator(LANG.quota);
        ADD_VALID["quota_number"].add("quota_value", "positive_integer", LANG.email_quota_number, "quota_number");
        ADD_VALID["quota_number"].attach();

        ADD_VALID["quota_unlimited"] = new CPANEL.validate.validator(LANG.quota);
        ADD_VALID["quota_unlimited"].add("quota_unlimited", "anything", "", "quota_unlimited");
        ADD_VALID["quota_unlimited"].attach();
    }

    CPANEL.validate.attach_to_form("ftp_create_submit", ADD_VALID, add_ftp_account);
    CPANEL.util.catch_enter(["login", "domain", "password", "password2", "homedir", "quota_value"], "ftp_create_submit");

    try {
        DOM.get("login").focus();
    } catch (e) {
    }
};

var suggest_homedir = function(public_html_only) {
    if ( public_html_only != 0 ) {
        DOM.get("homedir").value = "public_html/" + DOM.get("domain").value + "/" + DOM.get("login").value;
    } else {
        DOM.get("homedir").value = DOM.get("domain").value + "/" + DOM.get("login").value;
    }
    ADD_VALID["dir"].verify();
};

var toggle_add_account_quota = function(select_number) {
    if (select_number == true) {
        YAHOO.util.Dom.get("quota_number").checked = true;
    }

    if (YAHOO.util.Dom.get("quota_number").checked == true) {
        YAHOO.util.Dom.removeClass("quota_value", "dim-text");
        ADD_VALID["quota_number"].verify();
        ADD_VALID["quota_unlimited"].clear_messages();
    } else {
        YAHOO.util.Dom.addClass("quota_value", "dim-text");
        ADD_VALID["quota_number"].clear_messages();
        ADD_VALID["quota_unlimited"].verify();
    }
};

var load_accounts_table = function() {
    var columns = (SERVER_TYPE === "PURE") ? PURE_ACCOUNTS_TABLE_COLUMNS : PRO_ACCOUNTS_TABLE_COLUMNS;

    var callback = {
        success: function(o) {
            var result = {};
            try {
                result = YAHOO.lang.JSON.parse(o.responseText);
            } catch (e) {
                generate_table_message("accounts_div", "danger", CPANEL.icons.error + " " + LOCALE.maketext("JSON parse failed."), columns);
            }
            if (result.status) {
                build_accounts_table(result);
            } else {
                generate_table_message("accounts_div", "danger", CPANEL.icons.error + " " + LOCALE.maketext("Unknown Error"), columns);
            }
            TABLE_REQUEST_ACTIVE = false;
        },

        failure: function(o) {
            generate_table_message("accounts_div", "danger", CPANEL.icons.error + " " + LOCALE.maketext("AJAX Error") + ": " + LOCALE.maketext("Please refresh the page and try again."), columns);
            TABLE_REQUEST_ACTIVE = false;
        }
    };

    // send the AJAX request
    TABLE_REQUEST_ACTIVE = true;
    var url = CPANEL.urls.uapi("Ftp", "list_ftp_with_disk", FTP_UAPI_CALL);
    YAHOO.util.Connect.asyncRequest("GET", url, callback, "");

    close_all_path_popups();
    generate_table_message("accounts_div", "info", CPANEL.icons.ajax + " " + LOCALE.maketext("Loading …"), columns);
};

var load_special_accounts_table = function() {
    var columns = (SERVER_TYPE === "PURE") ? PURE_SPECIAL_ACCOUNTS_TABLE_COLUMNS : PRO_SPECIAL_ACCOUNTS_TABLE_COLUMNS;

    // build the call
    var args = {
        "include_acct_types": "anonymous|logaccess|main",
        "api.sort_column": "serverlogin",
        "api.sort_method": "alphabet",
        "api.sort_reverse": 0
    };

    var callback = {
        success: function(o) {
            try {
                var result = YAHOO.lang.JSON.parse(o.responseText);
                if (result.status) {
                    build_special_accounts_table(result);
                } else {
                    generate_table_message("special_accounts_div", "danger", CPANEL.icons.error + " " + LOCALE.maketext("Unknown Error"), columns);
                }
            } catch (e) {
                generate_table_message("special_accounts_div", "danger", CPANEL.icons.error + " " + LOCALE.maketext("JSON parse failed."), columns);
            }
        },

        failure: function(o) {
            generate_table_message("special_accounts_div", "danger", CPANEL.icons.error + " " + LOCALE.maketext("AJAX Error") + ": " + LOCALE.maketext("Please refresh the page and try again."), columns);
        }
    };

    // send the AJAX request
    var url = CPANEL.urls.uapi("Ftp", "list_ftp_with_disk", args);
    YAHOO.util.Connect.asyncRequest("GET", url, callback, "");

    generate_table_message("special_accounts_div", "info", CPANEL.icons.ajax + " " + LOCALE.maketext("Loading …"), columns);
};


var build_accounts_table = function(result) {
    var html = "";
    var row = "";
    var i = 0;
    var columns = (SERVER_TYPE === "PURE") ? PURE_ACCOUNTS_TABLE_COLUMNS : PRO_ACCOUNTS_TABLE_COLUMNS;
    var accounts = result.data;
    var accounts_length = accounts.length;
    if (accounts_length === 0) {
        generate_table_message("accounts_div", "info", LANG.no_accounts_found, columns);
        return;
    }

    for (i = 0; i < accounts_length; i++) {
        var zebra = (i % 2) ? "row-even" : "row-odd";

        // convert humandiskquota to MB or infinity symbol
        /* jshint -W116*/
        if (accounts[i].diskquota == 0 || accounts[i].diskquota == "unlimited") {
        /* jshint +W116*/
            accounts[i].diskquota = 0;
            accounts[i].humandiskquota = "&infin;";
        } else {

            // convert disk quota to integer
            accounts[i].diskquota = parseInt(accounts[i].diskquota, 10);
            accounts[i].humandiskquota = accounts[i].diskquota;
        }

        // convert usage to integer
        accounts[i].diskused = parseInt(accounts[i].diskused, 10);

        var login = accounts[i].login,
            urlLogin = encodeURIComponent(login),
            dns = encodeURIComponent(DNS),
            tplArgs = {
                index: i,
                login: login,
                home: accounts[i].dir
            },
            configureClientArgs = {
                index: i,
                login: accounts[i].serverlogin,
                server: FTP_SERVER,
                port: FTP_PORT,
                token: CPANEL.security_token,
                urlLogin: urlLogin,
                dns: dns,
                clients: FTP_CLIENTS,
                params: urlLogin + "|ftp." + dns + "|" + urlLogin
            };

        if (SERVER_TYPE === "PURE") {
            row = '<tr class="' + zebra + '" id="account_row_[% i %]">';
            row += '<td class="col1" data-title="' + LOCALE.maketext("Log In") + '">[% serverlogin %]<input type="hidden" id="login_[% i %]" value="[% login %]" /></td>';
            row += '<td class="col2" data-title="' + LOCALE.maketext("Path") + '">[% path %]</td>';
            row += '<td class="col3" data-title="' + LOCALE.maketext("Usage") + " / " + LOCALE.maketext("Quota") + '">[% diskused %] / <span id="humandiskquota_[% i %]">[% humandiskquota %]</span> <span class="megabyte_font">MB</span><input type="hidden" id="diskused_[% i %]" value="[% diskused %]" /><input type="hidden" id="diskquota_[% i %]" value="[% diskquota %]" /><br /><div style="height: 3px"></div><div id="usage_bar_[% i %]" class="table_progress_bar"></div></td>';
            row += '<td data-title="' + LOCALE.maketext("Actions") + '">';
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'changepassword_module_[% i %]\')">' + '<span class="fas fa-key"></span> ' + LANG.change_br_password + "</button>";
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'changequota_module_[% i %]\')">' + '<span class="glyphicon glyphicon-pencil"></span> ' + LANG.change_br_quota + "</button>";
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'delete_module_[% i %]\')">' + '<span class="glyphicon glyphicon-trash"></span> ' + LANG.Delete + "</button>";
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'config_module_[% i %]\')">' + '<span class="fas fa-cog"></span> ' + LANG.configure_ftp_client + "</button>";
            row += "</td>";
            row += "</tr>";

            row += '<tr class="action-row"><td class="editFormRow" colspan="' + columns + '">';
            row += changePasswordTpl(tplArgs);
            row += changeQuotaTpl(tplArgs);
            row += deleteAccountTpl(tplArgs);
            row += configureClientTpl(configureClientArgs);
            row += '<div id="status_bar_[% i %]" class="cjt_status_bar"></div>';
            row += "</td></tr>";
        } else {
            row = '<tr class="' + zebra + '" id="account_row_[% i %]">';
            row += '<td class="pro_col1" data-title="' + LOCALE.maketext("Log In") + '">[% serverlogin %]<input type="hidden" id="login_[% i %]" value="[% login %]" /></td>';
            row += '<td class="pro_col2" data-title="' + LOCALE.maketext("Path") + '">[% path %]</td>';
            row += '<td data-title="' + LOCALE.maketext("Actions") + '">';
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'changepassword_module_[% i %]\')">' + '<span class="fas fa-key"></span> ' + LANG.change_br_password + "</button>";
            row += '<button type="button" span class="btn btn-link" onclick="toggle_module(\'delete_module_[% i %]\')">' + '<span class="glyphicon glyphicon-trash"></span> ' + LANG.Delete + "</button>";
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'config_module_[% i %]\')">' + '<span class="fas fa-cog"></span> ' + LANG.configure_ftp_client + "</button>";
            row += "</td>";
            row += "</tr>";
            row += '<tr class="action-row"><td class="editFormRow" colspan="' + columns + '">';
            row += changePasswordTpl(tplArgs);
            row += deleteAccountTpl(tplArgs);
            row += configureClientTpl(configureClientArgs);
            row += '<div id="status_bar_[% i %]" class="cjt_status_bar"></div>';
            row += "</td></tr>";
        }

        // TODO: replace this using YAHOO.lang.substitute
        row = row.replace(/\[% i %\]/g, i);
        row = row.replace(/\[% login %\]/g, accounts[i].login);
        row = row.replace(/\[% serverlogin %\]/g, accounts[i].serverlogin);
        row = row.replace(/\[% path %\]/g, format_path(accounts[i].dir));
        row = row.replace(/\[% special_path %\]/g, format_path(accounts[i].dir, "delete_account2_" + i, i));
        row = row.replace(/\[% diskused %\]/g, accounts[i].diskused);
        row = row.replace(/\[% humandiskquota %\]/g, accounts[i].humandiskquota);
        row = row.replace(/\[% diskquota %\]/g, accounts[i].diskquota);
        row = row.replace(/\[% url.acct %\]/g, encodeURIComponent(accounts[i].login));
        row = row.replace(/\[% url.accttype %\]/g, encodeURIComponent(accounts[i].accttype));
        row = row.replace(/\[% ftp_port %\]/g, FTP_PORT);
        row = row.replace(/\[% sftp_port %\]/g, SFTP_PORT);
        row = row.replace(/\[% ftp_server %\]/g, FTP_SERVER);
        row = row.replace(/\[% url.dns %\]/g, encodeURIComponent(DNS));
        html += row;
    }

    insert_html_into_table("accounts_div", html);
    YAHOO.util.Dom.get("pagination").innerHTML = add_pagination(result.metadata.paginate);

    if (SERVER_TYPE === "PURE") {
        for (i = 0; i < accounts_length; i++) {
            show_usage_bar("usage_bar_" + i, accounts[i].diskused, accounts[i].diskquota);
        }
    }
};

var add_pagination = function(paginate) {

    // turn pagination data into integers just in case
    for (var i in paginate) {
        if (paginate.hasOwnProperty(i)) {
            paginate[i] = parseInt(paginate[i]);
        }
    }

    // do not paginate if there is only one page
    if (paginate.total_pages == 1) {
        return "";
    }

    var ellipsis1 = 0;
    var ellipsis2 = 0;

    var html = '<div id="pagination_pages">';
    for (var i = 1; i <= paginate.total_pages; i++) {

        // bold the current page
        if (i == paginate.current_page) {
            html += ' <span class="paginate_current_page">' + i + "</span> ";
        } else if (i == 1 || i == paginate.total_pages) { // always show page 1 and the last page
            html += ' <span onclick="change_page(' + i + ')" class="paginate_page">' + i + "</span> ";
        } else if (i < paginate.current_page - 2) { // show ellipsis for any pages less than 3 away
            if (ellipsis1 == 0) {
                html += "...";
                ellipsis1 = 1;
            }
        } else if (i > paginate.current_page + 2) { // show ellipsis for any pages more than 3 away
            if (ellipsis2 == 0) {
                html += "...";
                ellipsis2 = 1;
            }
        } else {
            html += ' <span onclick="change_page(' + i + ')" class="paginate_page">' + i + "</span> ";
        }
    }
    html += "</div>";

    html += '<div id="pagination_links">';
    if (paginate.current_page != 1) {
        var prev_page = paginate.current_page - 1;
        html += '<span onclick="change_page(' + prev_page + ')" class="paginate_prev">&larr; ' + LANG.paginate_prev + "</span> ";
    }
    if (paginate.current_page != paginate.total_pages) {
        var next_page = paginate.current_page + 1;
        html += ' <span onclick="change_page(' + next_page + ')" class="paginate_next">' + LANG.paginate_next + " &rarr;</span>";
    }
    html += "</div>";

    return html;
};

var build_special_accounts_table = function(result) {
    var special_panels1 = [];
    var special_panels2 = [];
    YAHOO.util.Dom.get("list_of_anonymous_account_ids").value = "";
    var html = "";
    var row = "";
    var i = 0;
    var columns = (SERVER_TYPE === "PURE") ? PURE_SPECIAL_ACCOUNTS_TABLE_COLUMNS : PRO_SPECIAL_ACCOUNTS_TABLE_COLUMNS;

    var accounts = result.data;
    for (i = 0; i < accounts.length; i++) {
        var zebra = (i % 2) ? "row-even" : "row-odd";

        // convert humandiskquota to MB or infinity symbol
        /* jshint -W116 */
        if (accounts[i].diskquota == 0 || accounts[i].diskquota == "unlimited") {
        /* jshint +W116 */
            accounts[i].diskquota = 0;
            accounts[i].humandiskquota = "&infin;";
        } else {

            // convert disk quota to integer
            accounts[i].diskquota = parseInt(accounts[i].diskquota, 10);
            accounts[i].humandiskquota = accounts[i].diskquota;
        }

        // convert usage to integer
        accounts[i].diskused = parseInt(accounts[i].diskused, 10);


        var is_system_account = (accounts[i].serverlogin === CPANEL_USER);
        var special_main_description = YAHOO.util.Dom.get("special_main_description").innerHTML.trim();
        var special_anon_description = YAHOO.util.Dom.get("special_anon_description").innerHTML.trim();
        var special_log_description = YAHOO.util.Dom.get("special_log_description").innerHTML.trim();

        var login = accounts[i].login,
            urlLogin = encodeURIComponent(login),
            dns = encodeURIComponent(DNS),
            tplArgs = {
                index: "special" + i,
                isSpecial: true,
                login: login
            },
            configureClientArgs = {
                isSystem: accounts[i].accttype === "main",
                index: "special" + i,
                login: accounts[i].serverlogin,
                server: FTP_SERVER,
                port: FTP_PORT,
                token: CPANEL.security_token,
                urlLogin: urlLogin,
                dns: dns,
                clients: FTP_CLIENTS,
                params: urlLogin + "|ftp." + dns + "|" + urlLogin
            };

        if (SERVER_TYPE === "PURE") {
            row = '<tr class="' + zebra + '">';
            if (accounts[i].accttype === "main") {
                row += '<td class="special_col1" data-title="' + LOCALE.maketext("Type") + '"><i class="fas fa-user" aria-hidden="true" id="special_image_[% i %]" title="' + special_main_description + '"></i></td>';

            }
            if (accounts[i].accttype === "anonymous") {
                row += '<td class="special_col1" data-title="' + LOCALE.maketext("Type") + '"><i class="fas fa-user-secret" aria-hidden="true" id="special_image_[% i %]" title="' + special_anon_description + '"></i></td>';

                YAHOO.util.Dom.get("list_of_anonymous_account_ids").value += "special" + i + "|";
            }
            if (accounts[i].accttype === "logaccess") {
                row += '<td class="special_col1" data-title="' + LOCALE.maketext("Type") + '"><i class="fas fa-file" aria-hidden="true" id="special_image_[% i %]" title="' + special_log_description + '"></i></td>';

            }
            row += '<td class="special_col2" data-title="' + LOCALE.maketext("Log In") + '">[% serverlogin %]<input type="hidden" id="login_[% i %]" value="[% login %]" /></td>';
            row += '<td class="special_col3" data-title="' + LOCALE.maketext("Path") + '">[% path %]</td>';
            row += '<td class="special_col4" data-title="' + LOCALE.maketext("Usage") + " / " + LOCALE.maketext("Quota") + '">[% diskused %] / <span id="humandiskquota_[% i %]">[% humandiskquota %]</span> <span class="megabyte_font">MB</span><input type="hidden" id="diskused_[% i %]" value="[% diskused %]" /><input type="hidden" id="diskquota_[% i %]" value="[% diskquota %]" /><br /><div style="height: 3px"></div><div id="usage_bar_[% i %]" class="table_progress_bar"></div></td>';
            row += '<td data-title="' + LOCALE.maketext("Actions") + '">';

            if (accounts[i].accttype === "main") {
                row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'config_module_[% i %]\')">' + '<span class="fas fa-cog"></span> ' + LANG.configure_ftp_client + "</button>";
            }
            if (accounts[i].accttype === "anonymous") {
                row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'changequota_module_[% i %]\')">' + '<span class="glyphicon glyphicon-pencil"></span> ' + LANG.change_br_quota + "</button>";
                row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'config_module_[% i %]\')">' + '<span class="fas fa-cog"></span> ' + LANG.configure_ftp_client + "</button>";
            }
            if (accounts[i].accttype === "logaccess") {
                row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'config_module_[% i %]\')">' + '<span class="fas fa-cog"></span> ' + LANG.configure_ftp_client + "</button>";
            }

            row += "</td>";
            row += "</tr>";

            row += '<tr class="action-row"><td class="editFormRow" colspan="' + columns + '">';

            // row += build_configureanon_module();
            row += changeQuotaTpl(tplArgs);
            row += configureClientTpl(configureClientArgs);
            row += '<div id="status_bar_[% i %]" class="cjt_status_bar"></div>';
            row += "</td></tr>";
        } else {
            row = '<tr class="' + zebra + '">';
            if (accounts[i].accttype === "main") {
                row += '<td class="pro_special_col1" data-title="' + LOCALE.maketext("Type") + '"><i class="fas fa-user" aria-hidden="true" id="special_image_[% i %]" title="' + special_main_description + '"></i></td>';
            }
            if (accounts[i].accttype === "anonymous") {
                row += '<td class="pro_special_col1" data-title="' + LOCALE.maketext("Type") + '"><i class="fas fa-user-secret" aria-hidden="true" id="special_image_[% i %]" title="' + special_anon_description + '"></i></td>';
            }
            if (accounts[i].accttype === "logaccess") {
                row += '<td class="pro_special_col1" data-title="' + LOCALE.maketext("Type") + '"><i class="fas fa-file" aria-hidden="true" id="special_image_[% i %]" title="' + special_log_description + '"></i></td>';
            }
            row += '<td class="pro_special_col2" data-title="' + LOCALE.maketext("Log In") + '">[% serverlogin %]<input type="hidden" id="login_[% i %]" value="[% login %]" /></td>';
            row += '<td class="pro_special_col3" data-title="' + LOCALE.maketext("Path") + '">[% path %]</td>';
            row += '<td data-title="' + LOCALE.maketext("Actions") + '">';
            row += '<button type="button" class="btn btn-link" onclick="toggle_module(\'config_module_[% i %]\')">' + '<span class="fas fa-cog"></span> ' + LANG.configure_ftp_client + "</button>";
            row += "</td>";
            row += "</tr>";

            row += '<tr class="action-row"><td class="editFormRow" colspan="' + columns + '">';
            row += changePasswordTpl(tplArgs);
            row += configureClientTpl(configureClientArgs);
            row += '<div id="status_bar_[% i %]" class="cjt_status_bar"></div>';
            row += "</td></tr>";
        }

        row = row.replace(/\[% i %\]/g, "special" + i);
        row = row.replace(/\[% type %\]/g, accounts[i].accttype);
        row = row.replace(/\[% login %\]/g, accounts[i].login);
        row = row.replace(/\[% serverlogin %\]/g, accounts[i].serverlogin);
        row = row.replace(/\[% path %\]/g, format_path(accounts[i].dir));
        row = row.replace(/\[% diskused %\]/g, accounts[i].diskused);
        row = row.replace(/\[% humandiskquota %\]/g, accounts[i].humandiskquota);
        row = row.replace(/\[% diskquota %\]/g, accounts[i].diskquota);
        row = row.replace(/\[% url.acct %\]/g, encodeURIComponent(accounts[i].login));
        row = row.replace(/\[% url.accttype %\]/g, encodeURIComponent(accounts[i].accttype));
        row = row.replace(/\[% ftp_port %\]/g, FTP_PORT);
        row = row.replace(/\[% sftp_port %\]/g, SFTP_PORT);
        row = row.replace(/\[% ftp_server %\]/g, FTP_SERVER);
        row = row.replace(/\[% url.dns %\]/g, encodeURIComponent(DNS));
        html += row;
    }

    insert_html_into_table("special_accounts_div", html);

    // create the help panels
    if (special_panels1.length > 0) {
        for (i = 0; i < special_panels2.length; i++) {
            CPANEL.panels.create_help(special_panels1[i], special_panels2[i]);
        }
    }

    // build the progress bars
    if (SERVER_TYPE === "PURE") {
        for (i = 0; i < accounts.length; i++) {
            show_usage_bar("usage_bar_special" + i, accounts[i].diskused, accounts[i].diskquota);
        }
    }
};

var toggle_delete_home_message = function(index) {
    var checkbox = document.getElementById("delete_account_files_" + index);
    var msg = document.getElementById("delete_home_dir_module_" + index );

    if (checkbox.checked) {
        msg.style.display = "block";
    } else {
        msg.style.display = "none";
    }
};

var toggle_module = function(id) {

    // close OPEN_MODULE if it's open
    if (OPEN_MODULE !== id && YAHOO.util.Dom.getStyle(OPEN_MODULE, "display") == "block") {
        var currently_open_div = OPEN_MODULE;
        before_hide_module(currently_open_div);
        CPANEL.animate.slide_up(currently_open_div, function() {
            after_hide_module(currently_open_div);
        });
    }

    // if id is currently displayed, hide it
    // The module's style:display property is interrogated in logic to determine if the element is visible.
    // It would be preferable to keep track of this logically or via an isVisible() function rather than relying on the element's style.
    if (YAHOO.util.Dom.getStyle(id, "display") != "none") {
        before_hide_module(id);
        CPANEL.animate.slide_up(id, function() {
            after_hide_module(id);
        });
    } else { // else show id and set it as the OPEN_MODULE
        before_show_module(id);
        CPANEL.animate.slide_down(id, function() {
            after_show_module(id);
        });
        OPEN_MODULE = id;
    }
};

var before_show_module = function(id) {
    var temp = id.split("_");
    var action = temp[0];
    var index = temp[2];

    if (action == "changepassword") {
        CHANGE_PASS_VALID = CPANEL.password.setup("change_password_1_" + index, "change_password_2_" + index, "password_strength_" + index, REQUIRED_PASSWORD_STRENGTH, "password_generator_" + index);
        CPANEL.validate.attach_to_form("change_password_" + index, CHANGE_PASS_VALID, function() {
            change_password(index);
        });
    }
    if (action == "changequota") {
        CHANGE_QUOTA_VALID["number"] = new CPANEL.validate.validator(LANG.quota);
        CHANGE_QUOTA_VALID["number"].add("change_quota_number_input_" + index, "positive_integer", LANG.quota_positive_integer, "change_quota_radio_number_" + index);
        CHANGE_QUOTA_VALID["number"].attach();

        CHANGE_QUOTA_VALID["unlimited"] = new CPANEL.validate.validator(LANG.quota);
        CHANGE_QUOTA_VALID["unlimited"].add("change_quota_radio_unlimited_" + index, "anything", "", "change_quota_radio_unlimited_" + index);
        CHANGE_QUOTA_VALID["unlimited"].attach();

        CPANEL.validate.attach_to_form("change_quota_button_" + index, CHANGE_QUOTA_VALID, function() {
            change_quota(index);
        });

        var quota = parseInt(YAHOO.util.Dom.get("diskquota_" + index).value, 10);
        if (CPANEL.validate.integer(quota) == true && quota != 0) {
            YAHOO.util.Dom.get("change_quota_number_input_" + index).value = quota;
            toggle_quota_input("number", index);
        } else {
            YAHOO.util.Dom.get("change_quota_number_input_" + index).value = 2000;
            toggle_quota_input("unlimited", index);
        }
    }
};

var before_hide_module = function(id) {
    var temp = id.split("_");
    var action = temp[0];
    var index = temp[2];

    if (action == "changepassword") {
        CHANGE_PASS_VALID[0].clear_messages();
        CHANGE_PASS_VALID[1].clear_messages();
        YAHOO.util.Event.purgeElement("changepassword_module_" + index, true);
    }
    if (action == "changequota") {
        CHANGE_QUOTA_VALID["number"].clear_messages();
        CHANGE_QUOTA_VALID["unlimited"].clear_messages();
        YAHOO.util.Event.purgeElement("changequota_module_" + index, true);
    }
};

var after_show_module = function(id) {
    var temp = id.split("_");
    var action = temp[0];
    var index = temp[2];

    if (action == "changepassword") {
        YAHOO.util.Dom.get("change_password_1_" + index).focus();
        CPANEL.util.catch_enter(["change_password_1_" + index, "change_password_2_" + index], "change_password_" + index);
    }
    if (action == "changequota") {
        CPANEL.util.catch_enter("change_quota_number_input_" + index, "change_quota_button_" + index);
    }
    CPANEL.align_panels_event.fire();
};

var after_hide_module = function(id) {
    var temp = id.split("_");
    var action = temp[0];
    var index = temp[2];

    if (action == "changepassword") {
        YAHOO.util.Dom.get("change_password_1_" + index).value = "";
        YAHOO.util.Dom.get("change_password_2_" + index).value = "";
    }
    CPANEL.align_panels_event.fire();
};

var toggle_quota_input = function(mode, index, validate_and_focus) {
    if (mode == "number") {
        YAHOO.util.Dom.get("change_quota_radio_number_" + index).checked = true;
        YAHOO.util.Dom.get("change_quota_radio_unlimited_" + index).checked = false;
        YAHOO.util.Dom.removeClass("change_quota_number_input_" + index, "dim-text");

        if (validate_and_focus) {
            YAHOO.util.Dom.get("change_quota_number_input_" + index).focus();
            CHANGE_QUOTA_VALID["number"].verify();
            CHANGE_QUOTA_VALID["unlimited"].clear_messages();
        }
    } else {
        YAHOO.util.Dom.get("change_quota_radio_number_" + index).checked = false;
        YAHOO.util.Dom.get("change_quota_radio_unlimited_" + index).checked = true;
        YAHOO.util.Dom.addClass("change_quota_number_input_" + index, "dim-text");

        if (validate_and_focus) {
            CHANGE_QUOTA_VALID["number"].clear_messages();
            CHANGE_QUOTA_VALID["unlimited"].verify();
        }
    }
};

var format_path = function(path, hide_element, i) {
    var uid = YAHOO.util.Dom.generateId();
    var path2;
    if (path.length > 24) {
        if (hide_element) {
            path2 = path.slice(0, 12).html_encode() + '<span class="action_link" id="' + uid + '" style="text-decoration: underline" onclick="toggle_path_popup(\'' + uid + "', '" + hide_element + '\')">...</span>' + path.slice(path.length - 12).html_encode();
            path2 += '<input type="hidden" id="delete_module_path_popup_uid_' + i + '" value="' + uid + '" />';
        } else {
            path2 = path.slice(0, 12).html_encode() + '<span class="action_link" id="' + uid + '" style="text-decoration: underline" onclick="toggle_path_popup(\'' + uid + '\')">...</span>' + path.slice(path.length - 12).html_encode();
        }
        path2 += '<input type="hidden" id="' + uid + '_path" value="' + path.html_encode() + '" />';
    } else {
        if (hide_element) {
            path2 = path.html_encode() + "<input type='hidden' id='delete_module_path_popup_uid_" + i + "' value='" + uid + "' />";
        } else {
            path2 = path.html_encode();
        }
    }
    return path2;
};

var toggle_path_popup = function(id, hide_element) {
    var path = YAHOO.util.Dom.get(id + "_path").value;

    if (!PATH_POPUPS[id]) {

        // get the width of the path string
        var proxy_span = YAHOO.util.Dom.get("get_path_width");
        proxy_span.innerHTML = path.html_encode();
        var region = YAHOO.util.Region.getRegion(proxy_span);
        proxy_span.innerHTML = "";
        var path_width = region.width;

        // BROWSER-SPECIFIC CODE: pad the input width for webkit and gecko
        if (YAHOO.env.ua.webkit >= 1) {
            path_width += 12;
        }
        if (YAHOO.env.ua.gecko >= 1) {
            path_width += 15;
        }

        var options = {
            context: [id, "tl", "br", ["beforeShow", "windowResize", CPANEL.align_panels_event]],
            effect: {
                effect: YAHOO.widget.ContainerEffect.FADE,
                duration: 0.25
            },
            visible: false
        };
        PATH_POPUPS[id] = new YAHOO.widget.Overlay(id + "_overlay", options);

        var html = '<span class="action_link" onclick="toggle_path_popup(\'' + id + '\')">&nbsp;x&nbsp;</span><input readonly type="text" style="width: ' + path_width + 'px" value="' + path.html_encode() + '" onclick="this.select()" id="' + id + '_input" />';

        PATH_POPUPS[id].setBody(html);
        PATH_POPUPS[id].render(document.body);
        PATH_POPUPS[id].showEvent.subscribe(function() {
            YAHOO.util.Dom.get(id + "_input").select();
        });

        if (hide_element) {
            PATH_POPUPS[id].beforeShowEvent.subscribe(function() {
                YAHOO.util.Dom.get(hide_element).disabled = true;
            });
            PATH_POPUPS[id].hideEvent.subscribe(function() {
                YAHOO.util.Dom.get(hide_element).disabled = false;
            });
        }

        YAHOO.util.Dom.addClass(id + "_overlay", "path_popup");
    }

    if (PATH_POPUPS[id].cfg.getProperty("visible") == true) {
        PATH_POPUPS[id].hide();
    } else {
        PATH_POPUPS[id].show();
    }
};

var close_all_path_popups = function() {
    for (var i in PATH_POPUPS) {
        if (PATH_POPUPS.hasOwnProperty(i)) {
            PATH_POPUPS[i].hide();
        }
    }
};

var clear_add_account_input = function() {
    YAHOO.util.Dom.get("login").value = "";
    YAHOO.util.Dom.get("password").value = "";
    YAHOO.util.Dom.get("password2").value = "";
    YAHOO.util.Dom.get("homedir").value = "";
    if (SERVER_TYPE == "PURE") {
        YAHOO.util.Dom.get("quota_value").value = 2000;
        YAHOO.util.Dom.get("quota_unlimited").checked = true;
        toggle_add_account_quota();
    }
    CPANEL.password.show_strength_bar("password_strength", 0);
    for (var i in ADD_VALID) {
        if (ADD_VALID.hasOwnProperty(i)) {
            ADD_VALID[i].clear_messages();
        }
    }
};

var add_ftp_account = function() {
    var DOM = YAHOO.util.Dom;
    var user = DOM.get("login").value;
    var domain = DOM.get("domain").value;

    // create the API variables
    var args = {
        user: user,
        domain: domain,
        pass: DOM.get("password").value,
        homedir: DOM.get("homedir").value,
        disallowdot: 0
    };

    if (SERVER_TYPE != "PRO") {
        (DOM.get("quota_number").checked == true) ? args.quota = parseInt(DOM.get("quota_value").value, 10) : args.quota = 0;
    }

    var reset_input = function() {
        DOM.setStyle("ftp_create_submit", "display", "");
        DOM.get("add_ftp_status").innerHTML = "";
    };

    // callback functions
    var callback = {
        success: function(o) {
            try {
                var result = YAHOO.lang.JSON.parse(o.responseText);
            } catch (e) {
                CPANEL.widgets.status_bar("add_ftp_status_bar", "error", LOCALE.maketext("Error"), LOCALE.maketext("JSON parse failed."));
                reset_input();
                return;
            }

            if (result.status == "1") {
                CPANEL.widgets.status_bar("add_ftp_status_bar", "success", LANG.Account_Created, user);
                clear_add_account_input();
                load_accounts_table();
            } else if (result.status == "0") {
                CPANEL.widgets.status_bar("add_ftp_status_bar", "error", LOCALE.maketext("Error"), result.errors[0]);
            } else {
                CPANEL.widgets.status_bar("add_ftp_status_bar", "error", LOCALE.maketext("Error"), LOCALE.maketext("Unknown Error"));
            }

            reset_input();
        },

        failure: function(o) {
            CPANEL.widgets.status_bar("add_ftp_status_bar", "error", LOCALE.maketext("AJAX Error"), LOCALE.maketext("Please refresh the page and try again."));
            reset_input();
        }
    };

    // send the AJAX request
    var url = CPANEL.urls.uapi("Ftp", "add_ftp", args);
    YAHOO.util.Connect.asyncRequest("GET", url, callback, "");

    // show the ajax loading icon
    DOM.setStyle("ftp_create_submit", "display", "none");
    DOM.get("add_ftp_status").innerHTML = CPANEL.icons.ajax + " " + LANG.creating_account;
};

var change_password = function(id) {

    // create the API variables
    var args = {
        "user": YAHOO.util.Dom.get("login_" + id).value,
        "pass": YAHOO.util.Dom.get("change_password_1_" + id).value
    };

    var reset_input = function() {
        YAHOO.util.Dom.setStyle("change_password_input_" + id, "display", "block");
        YAHOO.util.Dom.get("change_password_status_" + id).innerHTML = "";
    };

    // callback functions
    var callback = {
        success: function(o) {
            try {
                var result = YAHOO.lang.JSON.parse(o.responseText);
            } catch (e) { // JSON parse error
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), LOCALE.maketext("JSON parse failed."));
                reset_input();
                return;
            }

            if (result.status == "1") {
                CPANEL.widgets.status_bar("status_bar_" + id, "success", LANG.Changed_Password);
                toggle_module("changepassword_module_" + id);
            } else if (result.status == "0") {
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), result.errors[0]);
            } else { // unknown error
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), LOCALE.maketext("Unknown Error"));
            }
            reset_input();
        },

        failure: function(o) {
            CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("AJAX Error"), LOCALE.maketext("Please refresh the page and try again."));
            reset_input();
        }
    };

    // send the AJAX request
    var url = CPANEL.urls.uapi("Ftp", "passwd", args);
    YAHOO.util.Connect.asyncRequest("GET", url, callback, "");

    // show the ajax loading icon
    YAHOO.util.Dom.setStyle("change_password_input_" + id, "display", "none");
    YAHOO.util.Dom.get("change_password_status_" + id).innerHTML = CPANEL.icons.ajax + " " + LANG.changing_password;
};

var change_quota = function(id) {

    // get the quota
    var quota, quota_text, quota_status;
    if (YAHOO.util.Dom.get("change_quota_radio_number_" + id).checked == true) {
        quota = parseInt(YAHOO.util.Dom.get("change_quota_number_input_" + id).value, 10);
        quota_text = quota;
        quota_status = quota + ' <span class="megabyte_font">MB</span>';
    } else {
        quota = 0;
        quota_text = "&infin;";
        quota_status = LANG.unlimited;
    }

    // create the API variables
    var args = {
        "user": YAHOO.util.Dom.get("login_" + id).value,
        "quota": quota
    };

    var reset_input = function() {
        YAHOO.util.Dom.setStyle("change_quota_input_" + id, "display", "block");
        YAHOO.util.Dom.get("change_quota_status_" + id).innerHTML = "";
    };

    // callback functions
    var callback = {
        success: function(o) {
            try {
                var result = YAHOO.lang.JSON.parse(o.responseText);
            } catch (e) { // JSON parse error
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), LOCALE.maketext("JSON parse failed."));
                reset_input();
                return;
            }

            // success
            if (result.status == "1") {
                CPANEL.widgets.status_bar("status_bar_" + id, "success", LANG.Changed_Quota, quota_status);
                toggle_module("changequota_module_" + id);
                if (id.search(/special/) != -1) {
                    var special_ids = YAHOO.util.Dom.get("list_of_anonymous_account_ids").value;
                    special_ids = special_ids.split("|");
                    for (var i = 0; i < special_ids.length; i++) {
                        if (special_ids[i] != "") {
                            YAHOO.util.Dom.get("humandiskquota_" + special_ids[i]).innerHTML = quota_text;
                            YAHOO.util.Dom.get("diskquota_" + special_ids[i]).value = quota;
                            show_usage_bar("usage_bar_" + special_ids[i], YAHOO.util.Dom.get("diskused_" + special_ids[i]).value, quota);
                        }
                    }
                } else {
                    YAHOO.util.Dom.get("humandiskquota_" + id).innerHTML = quota_text;
                    YAHOO.util.Dom.get("diskquota_" + id).value = quota;
                    show_usage_bar("usage_bar_" + id, YAHOO.util.Dom.get("diskused_" + id).value, quota);
                }
            } else if (result.status == "0") { // known error
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), result.errors[0]);
            } else { // unknown error
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), LOCALE.maketext("Unknown Error"));
            }

            // reset the input fields
            reset_input();
        },

        failure: function(o) {
            CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("AJAX Error"), LOCALE.maketext("Please refresh the page and try again."));
            reset_input();
        }
    };

    // send the AJAX request
    var url = CPANEL.urls.uapi("Ftp", "set_quota", args);
    YAHOO.util.Connect.asyncRequest("GET", url, callback, "");

    // show the ajax loading icon
    YAHOO.util.Dom.setStyle("change_quota_input_" + id, "display", "none");
    YAHOO.util.Dom.get("change_quota_status_" + id).innerHTML = CPANEL.icons.ajax + " " + LANG.changing_quota;
};

var show_usage_bar = function(id, usage, quota) {
    var percent = 100 * (usage / quota);
    if (quota == 0) {
        percent = 0;
    }
    CPANEL.widgets.progress_bar(id, percent, "", {
        inverse_colors: true
    });
};

var delete_account = function(id) {

    // create the API call
    var destroy = DOM.get("delete_account_files_" + id).checked,
        args = {
            user: DOM.get("login_" + id).value
        };
    if (destroy) {
        args.destroy = "1";
    }

    var setLoading = function(loading) {
        DOM.get("cancel_delete_" + id).disabled = loading;
        DOM.get("delete_account_" + id).disabled = loading;
        DOM.get("delete_account_status_" + id)
            .innerHTML = loading ? CPANEL.icons.ajax + " " + LANG.deleting_account : "";
    };

    // callback functions
    var callback = {
        success: function(o) {
            try {
                var result = YAHOO.lang.JSON.parse(o.responseText);
            } catch (e) { // JSON parse error
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), LOCALE.maketext("JSON parse failed."));
                reset_input();
                return;
            }

            // error
            if (result.status == "0") {
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), result.errors[0]);
            } else if (result.status == "1") {  // success
                CPANEL.animate.fade_out("delete_module_" + id);
                CPANEL.animate.fade_out("account_row_" + id, function() {
                    if (FTP_ACCOUNTS_MAXED == true) {
                        FTP_ACCOUNTS_MAXED = false;
                        YAHOO.util.Dom.setStyle("new_ftp_account_input_div", "display", "");
                        YAHOO.util.Dom.setStyle("max_ftp_accounts_alert_box", "display", "none");
                    }
                });
            } else { // unknown
                CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("Error"), LOCALE.maketext("Unknown Error"));
            }

            setLoading(false);
        },

        failure: function(o) {
            CPANEL.widgets.status_bar("status_bar_" + id, "error", LOCALE.maketext("AJAX Error"), LOCALE.maketext("Please refresh the page and try again."));
            setLoading(false);
        }
    };

    // send the AJAX request
    var url = CPANEL.urls.uapi("Ftp", "delete_ftp", args);
    YAHOO.util.Connect.asyncRequest("GET", url, callback, "");

    // show the ajax loading icon
    setLoading(true);
};

var search_accounts = function() {

    // do not sort while a request is active
    if (TABLE_REQUEST_ACTIVE) {
        return;
    }

    var search_term = YAHOO.util.Dom.get("search_input").value;

    // do not search for the same thing two times in a row
    if (search_term == LAST_SEARCH_TXT) {
        return;
    }
    LAST_SEARCH_TXT = search_term;

    FTP_UAPI_CALL["api.filter_type"] = "contains";
    FTP_UAPI_CALL["api.filter_column"] = "serverlogin";
    FTP_UAPI_CALL["api.filter_term"] = search_term;

    // reset to page 1
    reset_pagination();

    load_accounts_table();

    // toggle the "clear search" button
    (search_term == "") ? YAHOO.util.Dom.setStyle("clear_search", "display", "none") : YAHOO.util.Dom.setStyle("clear_search", "display", "");
};

var clear_search = function() {
    YAHOO.util.Dom.get("search_input").value = "";
    search_accounts();
};

var change_items_per_page = function() {
    if (TABLE_REQUEST_ACTIVE == false) {
        reset_pagination();
        FTP_UAPI_CALL["api.paginate_size"] = YAHOO.util.Dom.get("items_per_page").value;
        load_accounts_table();
    }
};

var change_page = function(page) {
    if (TABLE_REQUEST_ACTIVE == false) {
        FTP_UAPI_CALL["api.paginate_start"] = ((page - 1) * FTP_UAPI_CALL["api.paginate_size"]) + 1;
        load_accounts_table();
    }
};

var reset_pagination = function() {
    FTP_UAPI_CALL["api.paginate_start"] = 1;
    YAHOO.util.Dom.get("pagination").innerHTML = "";
};

// toggle sorting of table headers
var toggle_sort = function(column) {

    // do not sort while a request is active
    if (TABLE_REQUEST_ACTIVE) {
        return true;
    }

    var prefix = (SERVER_TYPE === "PURE") ? "pure_" : "pro_";

    // clear all sorting icons
    var sort_columns = [
        prefix + "sort_direction_serverlogin_img",
        prefix + "sort_direction_dir_img"
    ];
    if (SERVER_TYPE === "PURE") {
        sort_columns.push(prefix + "sort_direction_diskused_img");
        sort_columns.push(prefix + "sort_direction_diskquota_img");
    }
    YAHOO.util.Dom.removeClass(sort_columns, "icon-arrow-up");
    YAHOO.util.Dom.removeClass(sort_columns, "icon-arrow-down");

    // determine field and method to sort by
    if (column === "serverlogin") {
        FTP_UAPI_CALL["api.sort_column"] = "serverlogin";
        FTP_UAPI_CALL["api.sort_method"] = "alphabet";
    }
    if (column === "dir") {
        FTP_UAPI_CALL["api.sort_column"] = "dir";
        FTP_UAPI_CALL["api.sort_method"] = "alphabet";
    }
    if (column === "diskused") {
        FTP_UAPI_CALL["api.sort_column"] = "diskused";
        FTP_UAPI_CALL["api.sort_method"] = "numeric";
    }
    if (column === "diskquota") {
        FTP_UAPI_CALL["api.sort_column"] = "diskquota";
        FTP_UAPI_CALL["api.sort_method"] = "numeric_zero_as_max";
    }

    var direction_el = YAHOO.util.Dom.get(prefix + "sort_direction_" + column);
    var img_el = YAHOO.util.Dom.get(prefix + "sort_direction_" + column + "_img");
    if (direction_el.value === "asc") {
        direction_el.value = "desc";
        YAHOO.util.Dom.addClass(img_el, "icon-arrow-down");
        FTP_UAPI_CALL["api.sort_reverse"] = "1";
    } else {
        direction_el.value = "asc";
        YAHOO.util.Dom.addClass(img_el, "icon-arrow-up");
        FTP_UAPI_CALL["api.sort_reverse"] = "0";
    }

    // reset to page 1
    reset_pagination();

    load_accounts_table();
};

var prep_ui_server_type = function() {
    if (SERVER_TYPE == "PRO") {
        YAHOO.util.Dom.setStyle("add_new_quota_row", "display", "none");

        YAHOO.util.Dom.setStyle("pure_table_header", "display", "none");
        YAHOO.util.Dom.setStyle("pro_table_header", "display", "");

        YAHOO.util.Dom.setStyle("pure_special_table_header", "display", "none");
        YAHOO.util.Dom.setStyle("pro_special_table_header", "display", "");
    }
};

var init = function() {

    // change the UI based on the server type
    prep_ui_server_type();

    // initialize the API call
    FTP_UAPI_CALL = {
        include_acct_types: "sub",
        "api.paginate_size": 10,
        "api.paginate_start": 1,
        "api.sort_column": "serverlogin",
        "api.sort_method": "alphabet",
        "api.sort_reverse": 0
    };

    CPANEL.util.catch_enter("search_input", "search_button");

    init_add_validation();
    load_accounts_table();
    load_special_accounts_table();
};
YAHOO.util.Event.onDOMReady(init);
/* eslint-enable camelcase */
