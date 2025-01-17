//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sql_password.js
// Generated: /usr/local/cpanel/base/sharedjs/sql_password-hu.js
// Module:    legacy_shared/sql_password-hu
// Locale:    hu
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"Bezárás","OK":"OK","Setting password …":"Jelszó beállítása…","Success":"Siker","The system is asking you to set this PostgreSQL user’s password because you have renamed the user. This user will not be able to log in until you set its password (you may use the user’s previous password here).":"A rendszer azt kéri Öntől, hogy állítsa be ennek a PostgreSQL-felhasználónak a jelszavát, mert Ön átnevezte a felhasználót. Ez a felhasználó addig nem tud bejelentkezni, amíg Ön be nem állítja a jelszavát (itt használhatja a felhasználó korábbi jelszavát).","You have successfully set this user’s password.":"Ön sikeresen beállította ennek a felhasználónak a jelszavát."};

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
