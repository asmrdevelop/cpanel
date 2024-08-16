/*
This uses the following variables in window.PAGE:
    db_prefix   (string, or false-y to indicate no DB prefixing)

NOTE: The validation functions in here rely on HTML's "maxlength" attribute
(DOM: "maxLength") to restrict name lengths for dbs and dbusers. (The backend
API will catch it if the frontend subverts this restriction.)
*/
(function sql_js(window) {
    "use strict";

    var CPANEL = window.CPANEL;
    var DOM = window.DOM;

    var PAGE = window.PAGE;

    var NAME_LENGTH_LIMIT = {
        mysql: {
            database: 64,
            user: null,
        },
        postgresql: {
            database: 63,
            user: 63,
        },
    };

    var ANYTHING_BUT_PRINTABLE_7_BIT_ASCII = /[^\u0020-\u007e]/;
    var MYSQL_DB_NAME_WILDCARDS = /(_|%|\\)/g;

    // see note on filesystem characters here:
    // https://dev.mysql.com/doc/refman/5.1/en/identifiers.html
    var MYSQL_STARTED_ALLOWING_FILESYS_CHARACTERS = 50116;
    var MYSQL_STARTED_ALLOWING_LONG_USERNAMES = 100000;

    function verify_mysql_database_name(name) {
        name = (typeof name === "object") ? DOM.get(name).value : name;

        _verify_name_length_limit("mysql", "database", name);
        _verify_database_name_but_not_length(name);

        _verify_database_name_for_mysql(name);
    }

    function verify_mysql_username(name) {
        name = (typeof name === "object") ? DOM.get(name).value : name;

        _verify_name_length_limit("mysql", "user", name);
        _verify_dbuser_name_but_not_length(name);
    }

    function verify_postgresql_database_name(name) {
        name = (typeof name === "object") ? DOM.get(name).value : name;

        _verify_name_length_limit("postgresql", "database", name);
        _verify_database_name_but_not_length(name);
    }

    function verify_postgresql_username(name) {
        name = (typeof name === "object") ? DOM.get(name).value : name;

        _verify_name_length_limit("postgresql", "user", name);
        _verify_dbuser_name_but_not_length(name);
    }

    function _verify_name_length_limit(engine, type, name) {
        var max = get_name_length_limit(engine, type);

        // Consider DB prefixing (if set) for MySQL database names
        if (engine === "mysql" && type === "database") {
            if (PAGE && PAGE.db_prefix) {
                max -= (PAGE.db_prefix.length + 1); // +1 because the underscore is counted twice by MySQL
            }
        }

        var excess = CPANEL.util.byte_length(name) - max;
        if ( excess > 0 ) {
            throw LOCALE.maketext("This value is too long by [quant,_1,character,characters]. The maximum length is [quant,_2,character,characters].", excess, max);
        }
    }

    // remove if we ever work around the wildcards-count-as-two problem
    function _verify_special_mysql_wildcards_in_dbnames_case(name) {
        var escaped_length = name.replace(MYSQL_DB_NAME_WILDCARDS, "\\$1").length;
        var limit = get_name_length_limit("mysql", "database");

        // Consider DB prefixing (if set) for MySQL database names
        if (PAGE && PAGE.db_prefix) {
            limit -= (PAGE.db_prefix.length + 1); // +1 because the underscore is counted twice by MySQL
        }

        var excess = escaped_length - limit;
        if (excess > 0) {
            throw LOCALE.maketext("This database name has too many wildcard-sensitive characters ([list_and_quoted,_1]). The system stores each of these as two characters internally, up to a limit of [quant,_2,character,characters]. This name would take up [quant,_3,character,characters] of internal storage, which is [numf,_4] too many.", ["\\", "_", "%"], limit, escaped_length, excess);
        }
    }

    function add_prefix(name) {
        if (PAGE && PAGE.db_prefix) {
            name = PAGE.db_prefix + name;
        }

        return name;
    }

    function make_mysql_dbname_validator(el_id) {
        _set_maxlength(el_id, "mysql", "database");
        return _setup_dbname_validator(
            new CPANEL.validate.validator(LOCALE.maketext("Database Name")),
            "mysql",
            el_id
        );
    }
    function make_postgresql_dbname_validator(el_id) {
        _set_maxlength(el_id, "postgresql", "database");
        return _setup_dbname_validator(
            new CPANEL.validate.validator(LOCALE.maketext("[asis,PostgreSQL] Database Name")),
            "postgresql",
            el_id
        );
    }

    function make_mysql_username_validator(el_id) {
        _set_maxlength(el_id, "mysql", "user");
        return _setup_username_validator(
            new CPANEL.validate.validator(LOCALE.maketext("Database Username")),
            "mysql",
            el_id
        );
    }

    function make_postgresql_username_validator(el_id) {
        _set_maxlength(el_id, "postgresql", "user");
        return _setup_username_validator(
            new CPANEL.validate.validator(LOCALE.maketext("[asis,PostgreSQL] Username")),
            "postgresql",
            el_id
        );
    }

    // NOTE: This returns the DB engine's native length limit, regardless of DB prefixing.
    function get_name_length_limit(engine, type) {
        if (engine === "mysql" && type === "user") {
            _populate_name_length_limit();
        }
        return NAME_LENGTH_LIMIT[engine][type];
    }

    function _set_maxlength(el, engine, type) {
        var max_length = get_name_length_limit(engine, type);
        if (PAGE && PAGE.db_prefix) {
            max_length -= PAGE.db_prefix.length;
        }

        DOM.get(el).maxLength = max_length;
    }

    function _setup_dbname_validator(validator, dbengine, el_id) {
        _add_exception_atom_to_validator(
            validator,
            el_id,
            CPANEL.sql["verify_" + dbengine + "_database_name"]
        );

        validator.attach();

        return validator;
    }

    function _setup_username_validator(validator, dbengine, el_id) {
        _add_exception_atom_to_validator(
            validator,
            el_id,
            _verify_dbuser_name_but_not_length
        );

        validator.attach();

        return validator;
    }

    function _add_exception_atom_to_validator(validator, el_id, func) {
        validator.add(
            el_id,
            _boolean_for_cp_validator(func),
            _message_for_cp_validator(func)
        );
    }

    function _verify_dbuser_name_but_not_length(el) {
        var name = (typeof el === "object") ? DOM.get(el).value : el;

        if (!name) {
            throw LOCALE.maketext("A username cannot be empty.");
        }

        if (/[^A-Za-z0-9_-]/.test(name)) {
            throw LOCALE.maketext("The name of a database user on this system may include only the following characters: [join, ,_1]", "A-Z a-z 0-9 _ -".split(" "));
        }

        if (/^[0-9]/.test(name)) {
            throw LOCALE.maketext("Username cannot begin with a number.");
        }

        return true;
    }

    function _boolean_for_cp_validator(thrower) {
        return function() {
            try {
                thrower.apply(this, arguments);
                return true;
            } catch (e) {
                return false;
            }
        };
    }

    function _message_for_cp_validator(thrower) {
        return function() {
            try {
                thrower.apply(this, arguments);
                return;
            } catch (e) {
                return e;
            }
        };
    }

    // gives the number that DBD::mysql returns in “mysql_serverversion”
    function _mysql_version_string_to_number(verstr) {

        // Handle 5.5.5-10.1.11-MariaDB
        if (verstr.match(/mariadb/i)) {
            verstr = verstr.replace(/^[^-]+-/, "");
        }

        // Handle 10.1.11-MariaDB
        return parseInt(
            verstr
                .replace(/-.*/, "")
                .split(/\./)
                .map( function(s) {
                    return s.lpad(2, 0);
                } )
                .join("")
        );
    }

    function _verify_database_name_for_mysql(name) {
        if (name.substr(-1) === " ") {
            throw LOCALE.maketext("A database name cannot end with a space character.");
        }

        if ( /\\/.test(name) ) {
            throw LOCALE.maketext( "This system prohibits the backslash ([_1]) character in database names.", "\\" );
        }

        // remove if we ever work around the wildcards-count-as-two problem
        _verify_special_mysql_wildcards_in_dbnames_case(name);

        if (window.MYSQL_SERVER_VERSION && _mysql_version_string_to_number(window.MYSQL_SERVER_VERSION) < MYSQL_STARTED_ALLOWING_FILESYS_CHARACTERS) {
            if (/[\/\\.]/.test(name)) {
                throw LOCALE.maketext("This system’s database version ([_1]) prohibits the character “[_2]” in database names. Ask your administrator to upgrade to a newer version.", window.MYSQL_SERVER_VERSION, ".");
            }
        }

        return true;
    }

    function _verify_database_name_but_not_length(el) {
        var name = (typeof el === "object") ? DOM.get(el).value : el;

        if (!name) {
            throw LOCALE.maketext("A database name cannot be empty.");
        }

        if (ANYTHING_BUT_PRINTABLE_7_BIT_ASCII.test(name)) {
            throw LOCALE.maketext("This system allows only printable [asis,ASCII] characters in database names.");
        }

        if (/[`'"]/.test(name)) {
            throw LOCALE.maketext("This system prohibits the following [numerate,_1,character,characters] in database names: [join, ,_2]", 3, ["'", "\"", "`"]);
        }

        if ( /\//.test(name) ) {
            throw LOCALE.maketext( "This system prohibits the slash ([_1]) character in database names.", "/" );
        }

        return true;
    }

    function _populate_name_length_limit() {
        if (!window.MYSQL_SERVER_VERSION) {
            alert("The system failed to populate the “window.MYSQL_SERVER_VERSION” variable.");
        }
        if (NAME_LENGTH_LIMIT["mysql"]["user"] !== null) {
            return NAME_LENGTH_LIMIT["mysql"]["user"];
        }
        if (_mysql_version_string_to_number(window.MYSQL_SERVER_VERSION) >= MYSQL_STARTED_ALLOWING_LONG_USERNAMES) {

            // MariaDB has a max length of 80.
            // For future-proofing, we’ll plan for a world where we allow
            // up to 32-byte usernames, though. The prefix underscore
            // is one more character; so, the max we can allow is: 80 - 32 - 1 = 47.
            NAME_LENGTH_LIMIT["mysql"]["user"] = 47;
        } else {
            NAME_LENGTH_LIMIT["mysql"]["user"] = 16;
        }
        return NAME_LENGTH_LIMIT["mysql"]["user"];
    }

    CPANEL.sql = {
        add_prefix: add_prefix,

        make_mysql_dbname_validator: make_mysql_dbname_validator,
        make_mysql_username_validator: make_mysql_username_validator,
        make_postgresql_dbname_validator: make_postgresql_dbname_validator,
        make_postgresql_username_validator: make_postgresql_username_validator,

        verify_mysql_database_name: verify_mysql_database_name,
        verify_mysql_username: verify_mysql_username,
        verify_postgresql_database_name: verify_postgresql_database_name,
        verify_postgresql_username: verify_postgresql_username,

        get_name_length_limit: get_name_length_limit,
    };

}(window));
