//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sql_password.js
// Generated: /usr/local/cpanel/base/sharedjs/sql_password-pl.js
// Module:    legacy_shared/sql_password-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"Zamknij","OK":"OK","Setting password …":"Trwa ustawianie hasła…","Success":"Powodzenie","The system is asking you to set this PostgreSQL user’s password because you have renamed the user. This user will not be able to log in until you set its password (you may use the user’s previous password here).":"System monituje Cię o ustawienie tego hasła użytkownika PostgreSQL, ponieważ nazwa tego użytkownika została przez Ciebie zmieniona. Ten użytkownik nie będzie mógł się zalogować, dopóki nie ustawisz jego hasła (możesz tu użyć poprzedniego hasła tego użytkownika).","You have successfully set this user’s password.":"Pomyślnie ustawiono hasło tego użytkownika."};

    if (!this.LEXICON) {
        this.LEXICON = {};
    }

    for(var item in newLex) {
        if(newLex.hasOwnProperty(item)) {
            var value = newLex[item];
            if (typeof(value) === "string" && value !== "") {
                // Only add it if there is a value.
                this.LEXICON[item] = value;
            }
        }
    }
})();
//~~END-GENERATED~~
