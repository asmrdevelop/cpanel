//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sql_password.js
// Generated: /usr/local/cpanel/base/sharedjs/sql_password-it.js
// Module:    legacy_shared/sql_password-it
// Locale:    it
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"Chiudi","OK":"OK","Setting password …":"Impostazione password in corso…","Success":"Operazione completata","The system is asking you to set this PostgreSQL user’s password because you have renamed the user. This user will not be able to log in until you set its password (you may use the user’s previous password here).":"Il sistema richiede di impostare la password di questo utente PostgreSQL perché l’utente è stato ridenominato. L’utente non sarà in grado di eseguire l’accesso finché non si imposta la relativa password (è possibile utilizzare la password precedente dell’utente).","You have successfully set this user’s password.":"Impostazione della password di questo utente completata."};

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
