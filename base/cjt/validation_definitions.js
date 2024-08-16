/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/*
Validation Atoms (the lowest level of validation structure)
> contains a boolean function in one of the following formats: valid_chars, invalid_chars, valid, invalid, min_length, max_length, less_than, greater_than
> each method is accompanied with a message (msg)
> messages can have some limited variable interpolation

valid_chars, invalid_chars
> character string
> can contain three optional ranges: a-z, A-Z, 0-9
> msg has 1 variable available to it: %invalid_chars%

valid_regexp
> regular expression
> should be very basic and easy to read
> must work in both Perl and JavaScript
> if the input string finds a match against the regular expression the function returns true
> if the regular expression finds a match against the input string --> return true
> if the regular expression does not find a match against the input string --> return false

invalid_regexp
> regular expression
> should be very basic and easy to read
> must work in both Perl and JavaScript
> msg has 1 variable available to it: %invalid%
> if the input string finds a match against the regular expression the function returns false

max_length, min_length
> integer
> compares against the length of the string
> msg has no variables available

less_than, greater_than
> integer
> treats the string as an number, returns false if the string is not a number
> msg has no variables available
*/

CPANEL.validation_definitions = {
    "IPV4_ADDRESS": [{
        "min_length": "1",
        "msg": "IP Address cannot be empty."
    }, {
        "valid_chars": ".0-9",
        "msg": "IP Address must contain only digits and periods."
    }, {
        "valid_regexp": "/^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$/",
        "msg": "IP Address not formatted correctly.  ie: 4.2.2.2, 192.168.1.100"
    }],

    "IPV4_ADDRESS_NO_LOCAL_IPS": [
        "IPV4_ADDRESS", {
            "invalid_regexp": "/(127\\.0\\.0\\.1)|(0\\.0\\.0\\.0)/",
            "msg": "IP Address cannot be local.  ie: 127.0.0.1, 0.0.0.0"
        }
    ],

    "LOCAL_EMAIL": [{
        "min_length": "1",
        "msg": "Email cannot be empty."
    }, {
        "max_length": "128",
        "msg": "Email cannot be longer than 128 characters."
    }, {
        "invalid_chars": " ",
        "msg": "Email cannot contain spaces."
    }, {
        "invalid_regexp": "/\\.\\./",
        "msg": "Email cannot contain two consecutive periods."
    }, {
        "invalid_regexp": "/^\\./",
        "msg": "Email cannot start with a period."
    }, {
        "invalid_regexp": "/\\.$/",
        "msg": "Email cannot end with a period. %invalid%"
    }],

    "LOCAL_EMAIL_CPANEL": [
        "LOCAL_EMAIL", {
            "valid_chars": ".a-zA-Z0-9!#$=?^_{}~-",
            "msg": "Email contains illegal characters: %invalid_chars%"
        }
    ],

    "LOCAL_EMAIL_RFC": [
        "LOCAL_EMAIL", {
            "valid_chars": ".a-zA-Z0-9!#$%&'*+/=?^_`{|}~-",
            "msg": "Email contains illegal characters: %invalid_chars%"
        }
    ],

    "FULL_EMAIL": [{
        "min_length": "1",
        "msg": "Email cannot be empty."
    }, {
        "invalid_chars": " ",
        "msg": "Email cannot contain spaces."
    }, {
        "": "",
        "msg": ""
    }],

    "FULL_EMAIL_CPANEL": [

    ],

    "FULL_EMAIL_RFC": [

    ],

    "DOMAIN": [

    ],

    "SUBDOMAIN": [{
        "min_length": "1",
        "msg": "Subdomain cannot be empty."
    }, {
        "max_length": "63",
        "msg": "Subdomain cannot be longer than 63 characters."
    }, {
        "invalid_chars": " ",
        "msg": "Subdomain cannot contain spaces."
    }, {
        "invalid_regexp": "\\.\\.",
        "msg": "Subdomain cannot contain two consecutive periods."
    }, {
        "valid_chars": "a-zA-Z0-9_-.",
        "msg": "Subdomain contains invalid characters: %invalid_chars%"
    }],

    "FQDN": [

    ],

    "TLD": [

    ],

    "FTP_USERNAME": [

    ],

    "MYSQL_DB_NAME": [

    ],

    "MYSQL_USERNAME": [

    ],

    "POSTGRES_DB_NAME": [

    ],

    "POSTGRES_USERNAME": [

    ]
};
