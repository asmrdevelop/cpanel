//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/cjt/sql.js
// Generated: /usr/local/cpanel/base/cjt/sql-hu.js
// Module:    legacy_cjt/sql-hu
// Locale:    hu
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"A database name cannot be empty.":"Az adatbázisnév nem lehet üres.","A database name cannot end with a space character.":"A database name cannot end with a space character.","A username cannot be empty.":"A felhasználónév nem lehet üres.","Database Name":"Adatbázisnév","Database Username":"Database Username","The name of a database user on this system may include only the following characters: [join, ,_1]":"Az adatbázis neve ezen a rendszeren csak a következő karaktereket tartalmazhatja: [join, ,_1]","This database name has too many wildcard-sensitive characters ([list_and_quoted,_1]). The system stores each of these as two characters internally, up to a limit of [quant,_2,character,characters]. This name would take up [quant,_3,character,characters] of internal storage, which is [numf,_4] too many.":"This database name has too many wildcard-sensitive characters ([list_and_quoted,_1]). The system stores each of these as two characters internally, up to a limit of [quant,_2,character,characters]. This name would take up [quant,_3,character,characters] of internal storage, which is [numf,_4] too many.","This system allows only printable [asis,ASCII] characters in database names.":"This system allows only printable [asis,ASCII] characters in database names.","This system prohibits the backslash ([_1]) character in database names.":"This system prohibits the backslash ([_1]) character in database names.","This system prohibits the following [numerate,_1,character,characters] in database names: [join, ,_2]":"This system prohibits the following [numerate,_1,character,characters] in database names: [join, ,_2]","This system prohibits the slash ([_1]) character in database names.":"This system prohibits the slash ([_1]) character in database names.","This system’s database version ([_1]) prohibits the character “[_2]” in database names. Ask your administrator to upgrade to a newer version.":"This system’s database version ([_1]) prohibits the character “[_2]” in database names. Ask your administrator to upgrade to a newer version.","This value is too long by [quant,_1,character,characters]. The maximum length is [quant,_2,character,characters].":"Ez az érték [quant,_1,karakter,karakter] értékkel hosszabb a megengedettnél. A maximális hossz [quant,_2,karakter,karakter].","Username cannot begin with a number.":"A felhasználónév nem kezdődhet számmal.","[asis,PostgreSQL] Database Name":"[asis,PostgreSQL] Database Name","[asis,PostgreSQL] Username":"[asis,PostgreSQL] Username"};

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
